defmodule CartographBackend.SystemMetrics do
  @moduledoc "Collects OS, BEAM VM, and Oban metrics."

  import Ecto.Query
  alias CartographBackend.Repo

  def collect do
    %{
      cpu: cpu_metrics(),
      memory: memory_metrics(),
      disk: disk_metrics(),
      system: system_info(),
      oban: oban_metrics()
    }
  end

  # ── CPU ───────────────────────────────────────────────────────────────────────

  defp cpu_metrics do
    os_usage =
      try do
        case :cpu_sup.util() do
          n when is_number(n) -> n
          _ -> 0.0
        end
      rescue
        _ -> 0.0
      catch
        _ -> 0.0
      end

    schedulers = :erlang.system_info(:schedulers_online)

    %{
      usagePercent: Float.round(os_usage * 1.0, 1),
      beamUsagePercent: beam_cpu_percent(schedulers),
      schedulers: schedulers,
      logicalCores: :erlang.system_info(:logical_processors_available) |> normalize_cores()
    }
  end

  # CPU time spent by the BEAM process since last sample, as % of one core.
  # runtime = CPU ms across all schedulers; wall_clock = real ms elapsed.
  # Dividing by schedulers normalises to a "per-core equivalent" percentage.
  defp beam_cpu_percent(schedulers) do
    {_total_rt, rt_delta} = :erlang.statistics(:runtime)
    {_total_wall, wall_delta} = :erlang.statistics(:wall_clock)

    if wall_delta > 0 do
      pct = rt_delta / wall_delta / schedulers * 100
      Float.round(min(pct, 100.0), 1)
    else
      0.0
    end
  end

  defp normalize_cores(:unknown), do: :erlang.system_info(:schedulers_online)
  defp normalize_cores(n), do: n

  # ── Memory ────────────────────────────────────────────────────────────────────

  defp memory_metrics do
    os_mem =
      try do
        data = :memsup.get_system_memory_data()
        total = Keyword.get(data, :total_memory, 0)
        free = Keyword.get(data, :free_memory, 0)
        used = total - free

        %{
          totalMb: bytes_to_mb(total),
          usedMb: bytes_to_mb(used),
          freeMb: bytes_to_mb(free),
          usedPercent: safe_percent(used, total)
        }
      rescue
        _ -> %{totalMb: 0, usedMb: 0, freeMb: 0, usedPercent: 0.0}
      catch
        _ -> %{totalMb: 0, usedMb: 0, freeMb: 0, usedPercent: 0.0}
      end

    vm = :erlang.memory()

    vm_mem = %{
      totalMb: bytes_to_mb(vm[:total]),
      processesMb: bytes_to_mb(vm[:processes]),
      binaryMb: bytes_to_mb(vm[:binary]),
      codeMb: bytes_to_mb(vm[:code]),
      etsMb: bytes_to_mb(vm[:ets])
    }

    %{os: os_mem, vm: vm_mem}
  end

  # ── Disk ──────────────────────────────────────────────────────────────────────

  defp disk_metrics do
    try do
      :disksup.get_disk_data()
      |> Enum.map(fn {mount, size_kb, pct} ->
        %{
          mount: to_string(mount),
          totalGb: Float.round(size_kb / 1_048_576, 1),
          usedPercent: pct * 1.0
        }
      end)
      |> Enum.reject(fn d -> d.totalGb == 0.0 end)
      |> Enum.take(5)
    rescue
      _ -> []
    catch
      _ -> []
    end
  end

  # ── System info ───────────────────────────────────────────────────────────────

  defp system_info do
    {wall_ms, _} = :erlang.statistics(:wall_clock)

    %{
      uptimeSeconds: div(wall_ms, 1000),
      processCount: :erlang.system_info(:process_count),
      atomCount: :erlang.system_info(:atom_count),
      nodeName: node_name(),
      elixirVersion: System.version(),
      otpVersion: to_string(:erlang.system_info(:otp_release))
    }
  end

  # A non-distributed node shows up as nonode@nohost — in that case show the machine hostname.
  defp node_name do
    case node() do
      :nonode@nohost ->
        {:ok, hostname} = :inet.gethostname()
        to_string(hostname)

      name ->
        to_string(name)
    end
  end

  # ── Oban ──────────────────────────────────────────────────────────────────────

  defp oban_metrics do
    try do
      counts =
        from(j in Oban.Job, group_by: j.state, select: {j.state, count(j.id)})
        |> Repo.all()
        |> Map.new()

      %{
        available: Map.get(counts, "available", 0),
        executing: Map.get(counts, "executing", 0),
        scheduled: Map.get(counts, "scheduled", 0),
        retryable: Map.get(counts, "retryable", 0),
        discarded: Map.get(counts, "discarded", 0),
        completed: Map.get(counts, "completed", 0)
      }
    rescue
      _ -> %{available: 0, executing: 0, scheduled: 0, retryable: 0, discarded: 0, completed: 0}
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────

  defp bytes_to_mb(nil), do: 0
  defp bytes_to_mb(n), do: Float.round(n / 1_048_576, 1)

  defp safe_percent(_, 0), do: 0.0
  defp safe_percent(used, total), do: Float.round(used / total * 100, 1)
end
