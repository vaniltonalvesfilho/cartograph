import { ChangeDetectionStrategy, Component, OnInit, HostListener, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { IconComponent } from './icon.component';
import { RouterModule } from '@angular/router';
import { NavContextService } from '../services/nav-context.service';
import { TranslationService } from '../services/translation.service';

interface Section { id: string; label: string; children?: Section[] }

// ── Translatable content ──────────────────────────────────────────────────────

interface DocsContent {
  // TOC labels
  toc: { [id: string]: string };
  // Intro
  introTitle: string;
  introLead: string;
  introTip: string;
  // Concepts
  conceptsTitle: string;
  // Groups
  groupsTitle: string;
  groupsLead: string;
  groupLabelGroup: string;
  groupDescGroup: string;
  groupLabelProject: string;
  groupDescProject: string;
  groupLabelJob: string;
  groupDescJob: string;
  groupsNote: string;
  // Jobs
  jobsTitle: string;
  jobsLead: string;
  jobFieldName: string; jobDescName: string;
  jobFieldSlug: string; jobDescSlug: string;
  jobFieldId: string;   jobDescId: string;
  jobFieldDsl: string;  jobDescDsl: string;
  jobFieldCron: string; jobDescCron: string;
  jobFieldWin: string;  jobDescWin: string;
  jobsNote: string;
  // Access
  accessTitle: string;
  accessLead: string;
  accessW: string; accessWDesc: string;
  accessE: string; accessEDesc: string;
  accessN: string; accessNDesc: string;
  accessC: string; accessCDesc: string;
  accessNote: string;
  // DSL
  dslTitle: string; dslLead: string;
  // DSL basic
  dslBasicTitle: string; dslBasicLead: string;
  dslBasicNote1: string; dslBasicNote2: string; dslBasicNote3: string; dslBasicNote4: string;
  dslWarnTitle: string; dslWarnBody: string;
  // DSL values
  dslValTitle: string;
  dslValStr: string; dslValStrNote: string;
  dslValInt: string; dslValIntNote: string;
  dslValFloat: string; dslValFloatNote: string;
  dslValBool: string; dslValBoolNote: string;
  dslValWarn: string;
  // DSL use
  dslUseTitle: string; dslUseLead: string; dslUseNote: string;
  // Steps
  stepsTitle: string; stepsLead: string;
  // readDirectory
  sRdTitle: string; sRdDesc: string;
  sRdParamPath: string; sRdParamPathDesc: string;
  // filter
  sFTitle: string; sFDesc: string;
  sFParamExt: string; sFParamExtDesc: string;
  // transform
  sTTitle: string; sTDesc: string;
  sTParamOp: string; sTParamOpDesc: string;
  // validate
  sVTitle: string; sVDesc: string;
  sVParamEmail: string; sVParamEmailDesc: string;
  sVParamCpf: string; sVParamCpfDesc: string;
  sVParamCnpj: string; sVParamCnpjDesc: string;
  sVParamTel: string; sVParamTelDesc: string;
  sVParamCep: string; sVParamCepDesc: string;
  sVParamRegex: string; sVParamRegexDesc: string;
  sVParamPattern: string; sVParamPatternDesc: string;
  sVNote: string;
  // writeOutput
  sWoTitle: string; sWoDesc: string;
  sWoParamPath: string; sWoParamPathDesc: string;
  // queryDatabase
  sQTitle: string; sQDesc: string;
  sQParamSrc: string; sQParamSrcDesc: string;
  sQParamQuery: string; sQParamQueryDesc: string;
  sQParamKey: string; sQParamKeyDesc: string;
  sQParamParams: string; sQParamParamsDesc: string;
  // executeDatabase
  sETitle: string; sEDesc: string;
  sEParamSrc: string; sEParamSrcDesc: string;
  sEParamQuery: string; sEParamQueryDesc: string;
  sEParamRows: string; sEParamRowsDesc: string;
  sEParamCols: string; sEParamColsDesc: string;
  sEParamParams: string; sEParamParamsDesc: string;
  // parseXml
  sPxTitle: string; sPxDesc: string;
  sPxParamPath: string; sPxParamPathDesc: string;
  sPxParamKey: string; sPxParamKeyDesc: string;
  sPxParamRoot: string; sPxParamRootDesc: string;
  sPxParamRes: string; sPxParamResDesc: string;
  // writeXml
  sWxTitle: string; sWxDesc: string;
  sWxParamData: string; sWxParamDataDesc: string;
  sWxParamPath: string; sWxParamPathDesc: string;
  sWxParamRoot: string; sWxParamRootDesc: string;
  sWxParamRow: string; sWxParamRowDesc: string;
  // parseJson
  sPjTitle: string; sPjDesc: string;
  sPjParamPath: string; sPjParamPathDesc: string;
  sPjParamKey: string; sPjParamKeyDesc: string;
  sPjParamRoot: string; sPjParamRootDesc: string;
  sPjParamRes: string; sPjParamResDesc: string;
  sPjStructNote: string;
  // writeJson
  sWjTitle: string; sWjDesc: string;
  sWjParamData: string; sWjParamDataDesc: string;
  sWjParamPath: string; sWjParamPathDesc: string;
  sWjParamPretty: string; sWjParamPrettyDesc: string;
  // Cron
  cronTitle: string; cronLead: string; cronNote: string;
  cronEveryMin: string; cronEveryHour: string; cronEveryDay: string;
  cronWeekday: string; cronWeekdays: string; cronMonthly: string;
  cronEvery4h: string; cronEvery15m: string;
  // Datasources
  dsTitle: string; dsLead: string; dsNote: string; dsTestNote: string;
  dsMysqlLabel: string; dsPostgresLabel: string;
  // Release
  relTitle: string; relLead: string;
  relFieldRelease: string; relDescRelease: string;
  relFieldArchive: string; relDescArchive: string;
  relNote: string;
  // Common
  thParam: string; thType: string; thDefault: string; thDesc: string;
  thLevel: string; thValue: string; thCan: string;
  thField: string; thBehavior: string;
  thExpr: string; thMeaning: string;
  orManual: string; endNote: string; endLink: string;
  // Code examples
  codeBasic: string;
  codeUse: string;
  codeReadDir: string;
  codeFilter: string;
  codeTransform: string;
  codeValidate: string;
  codeWriteOutput: string;
  codeQueryDb: string;
  codeExecDb: string;
  codeParseXml: string;
  codeWriteXml: string;
  codeParseJson: string;
  codeJsonStruct: string;
  codeWriteJson: string;
}

const PT: DocsContent = {
  toc: {
    intro: 'Introdução', concepts: 'Conceitos', groups: 'Grupos & Projetos',
    jobs: 'Jobs', access: 'Níveis de Acesso', dsl: 'DSL — Sintaxe',
    'dsl-basic': 'Estrutura básica', 'dsl-values': 'Tipos de valores',
    'dsl-use': 'Referências entre jobs', steps: 'Steps disponíveis',
    's-readdir': 'readDirectory', 's-filter': 'filter', 's-transform': 'transform',
    's-validate': 'validate',
    's-write': 'writeOutput', 's-qdb': 'queryDatabase', 's-edb': 'executeDatabase',
    's-pxml': 'parseXml', 's-wxml': 'writeXml', 's-pjson': 'parseJson', 's-wjson': 'writeJson',
    cron: 'Agendamento (Cron)', datasources: 'Fontes de Dados', release: 'Janela de Execução',
  },
  introTitle: 'Cartograph — Documentação',
  introLead: 'Cartograph é um executor de tarefas distribuído. Você descreve <strong>jobs</strong> usando uma DSL simples, agrupa-os em <strong>projetos</strong> e os executa manualmente ou por agendamento (cron). Cada execução é rastreada com logs detalhados em tempo real.',
  introTip: '<strong>Começo rápido:</strong> crie um grupo → crie um projeto dentro dele → adicione um job com a DSL → clique em <em>Executar</em>.',
  conceptsTitle: 'Conceitos',
  groupsTitle: 'Grupos & Projetos',
  groupsLead: 'A hierarquia de organização é:',
  groupLabelGroup: 'Grupo', groupDescGroup: '— agrupa projetos relacionados (ex.: "Backend", "Integrações")',
  groupLabelProject: 'Projeto', groupDescProject: '— contém jobs e membros com permissões próprias',
  groupLabelJob: 'Job (Task)', groupDescJob: '— unidade executável, definida pela DSL',
  groupsNote: 'Projetos herdam membros do grupo pai, mas podem ter membros adicionais com níveis de acesso diferentes.',
  jobsTitle: 'Jobs',
  jobsLead: 'Um job possui:',
  jobFieldName: 'nome', jobDescName: 'Nome legível exibido na interface',
  jobFieldSlug: 'identificador', jobDescSlug: 'Slug único dentro do projeto (kebab-case)',
  jobFieldId: 'ID global', jobDescId: 'Gerado automaticamente (identificador-XXXXXXXX). Usado em referências entre jobs com use',
  jobFieldDsl: 'DSL', jobDescDsl: 'Código que define os steps a executar',
  jobFieldCron: 'Agendamento', jobDescCron: 'Expressão cron opcional para execução automática',
  jobFieldWin: 'Janela', jobDescWin: 'Período em que o job pode ser executado (release / archive)',
  jobsNote: 'Cada execução gera um <strong>registro</strong> com status, logs e duração. O histórico fica na aba <em>Histórico</em> da tela de edição.',
  accessTitle: 'Níveis de Acesso',
  accessLead: 'O Cartograph usa um sistema de permissões em cascata:',
  accessW: 'Wayfarer', accessWDesc: 'Visualizar projetos e execuções',
  accessE: 'Explorer', accessEDesc: '+ Executar jobs manualmente',
  accessN: 'Navigator', accessNDesc: '+ Criar e editar jobs, gerenciar membros',
  accessC: 'Cartographer', accessCDesc: 'Acesso total, incluindo excluir e administrar o sistema',
  accessNote: 'Permissões em <strong>grupos</strong> se propagam para todos os projetos filhos. Permissões diretas em um projeto sobrescrevem as herdadas do grupo.',
  dslTitle: 'DSL — Sintaxe', dslLead: 'A DSL (Domain Specific Language) do Cartograph descreve o pipeline de um job como uma sequência de steps nomeados.',
  dslBasicTitle: 'Estrutura básica',
  dslBasicLead: 'Cada job contém um bloco raiz com um <strong>identificador</strong> seguido de <code>{}</code>. Dentro dele, um ou mais <code>step</code>s separados por vírgula:',
  dslBasicNote1: 'O identificador do bloco raiz usa <strong>camelCase</strong> ou <strong>snake_case</strong> (sem hífens)',
  dslBasicNote2: 'Steps são separados por <strong>vírgula</strong> — exceto o último',
  dslBasicNote3: 'O nome do step é uma string com o tipo do step',
  dslBasicNote4: 'Cada step executa em ordem e pode passar dados para o próximo via <strong>estado compartilhado</strong>',
  dslWarnTitle: 'Atenção', dslWarnBody: 'Identificadores <strong>não aceitam hífens</strong>. Use <code>importarDados</code> em vez de <code>importar-dados</code>.',
  dslValTitle: 'Tipos de valores',
  dslValStr: 'String', dslValStrNote: 'Sempre entre aspas duplas',
  dslValInt: 'Inteiro', dslValIntNote: 'Sem aspas',
  dslValFloat: 'Decimal', dslValFloatNote: 'Ponto como separador',
  dslValBool: 'Booleano', dslValBoolNote: 'Minúsculo',
  dslValWarn: 'Listas literais <strong>não são suportadas</strong>. Para passar múltiplos valores use uma string CSV: <code>columns "nome,categoria,preco"</code>',
  dslUseTitle: 'Referências entre jobs (use)',
  dslUseLead: 'Um job pode depender de outro usando o <strong>ID global</strong> do job referenciado. O ID global aparece na tela de edição do job.',
  dslUseNote: 'Referências criam um grafo de dependência. O Cartograph detecta ciclos e impede execuções infinitas. Visualize o fluxo de um job na aba <em>Fluxo</em>.',
  stepsTitle: 'Steps disponíveis',
  stepsLead: 'Cada step recebe parâmetros e opera sobre o <strong>estado compartilhado</strong> da execução — um mapa de chave/valor que persiste entre steps.',
  sRdTitle: 'readDirectory', sRdDesc: 'Lê os arquivos de um diretório e armazena a lista no estado. Usado como ponto de entrada para pipelines de processamento de arquivos.',
  sRdParamPath: 'path', sRdParamPathDesc: 'Diretório a ser lido (relativo à raiz da aplicação)',
  sFTitle: 'filter', sFDesc: 'Filtra a lista de arquivos do estado por extensão. Geralmente usado após readDirectory.',
  sFParamExt: 'extension', sFParamExtDesc: 'Extensão sem ponto (ex.: "csv", "xml")',
  sTTitle: 'transform', sTDesc: 'Aplica uma transformação de texto ao conteúdo dos arquivos em memória.',
  sTParamOp: 'operation', sTParamOpDesc: '"uppercase" ou "lowercase"',
  sVTitle: 'validate', sVDesc: 'Valida o formato de campos do estado, no estilo do Bean Validation: cada parâmetro é um validador apontando para um campo (caminho com pontos; listas validam item a item). Qualquer violação interrompe o job listando todos os valores inválidos.',
  sVParamEmail: 'email', sVParamEmailDesc: 'Campo do estado com e-mail(s) a validar (ex.: "rows.email")',
  sVParamCpf: 'cpf', sVParamCpfDesc: 'Campo com CPF(s) — aceita "529.982.247-25" ou só dígitos; confere os dígitos verificadores',
  sVParamCnpj: 'cnpj', sVParamCnpjDesc: 'Campo com CNPJ(s) — numérico ou alfanumérico (formato 2026, ex.: "12.ABC.345/01DE-35"); confere os dígitos verificadores',
  sVParamTel: 'telefone', sVParamTelDesc: 'Campo com telefone(s) brasileiro(s) — DDD + celular (9 dígitos) ou fixo (8 dígitos), com ou sem +55 e formatação',
  sVParamCep: 'cep', sVParamCepDesc: 'Campo com CEP(s) — 8 dígitos, hífen opcional (ex.: "01310-100")',
  sVParamRegex: 'regex', sVParamRegexDesc: 'Campo a validar com uma expressão regular própria (exige o parâmetro pattern)',
  sVParamPattern: 'pattern', sVParamPatternDesc: 'A expressão regular usada pelo validador regex (ex.: "^[A-Z]{3}-[0-9]+$"; escreva \\\\d para \\d)',
  sVNote: 'Use pelo menos um dos validadores. Se o valor não corresponder a nenhum campo do state, ele é validado como literal (ex.: email "teste@example.com"); havendo o campo, ele tem precedência, e campo ausente numa lista conta como violação — o step funciona como um portão de qualidade antes de gravar ou exportar dados.',
  sWoTitle: 'writeOutput', sWoDesc: 'Grava os arquivos processados em um diretório de saída.',
  sWoParamPath: 'path', sWoParamPathDesc: 'Diretório de destino',
  sQTitle: 'queryDatabase', sQDesc: 'Executa uma query SELECT em uma fonte de dados e salva os resultados no estado. A fonte deve estar configurada pelo administrador e associada ao projeto.',
  sQParamSrc: 'source', sQParamSrcDesc: 'Slug da fonte de dados (ex.: "mysql-local")',
  sQParamQuery: 'query', sQParamQueryDesc: 'Query SQL a executar',
  sQParamKey: 'result_key', sQParamKeyDesc: 'Chave no estado onde os resultados serão salvos',
  sQParamParams: 'params', sQParamParamsDesc: 'Parâmetros bind separados por vírgula (prevenção de SQL Injection)',
  sETitle: 'executeDatabase', sEDesc: 'Executa uma query INSERT, UPDATE ou DELETE para cada linha de uma lista no estado.',
  sEParamSrc: 'source', sEParamSrcDesc: 'Slug da fonte de dados',
  sEParamQuery: 'query', sEParamQueryDesc: 'Query parametrizada com ? para MySQL ou $1,$2 para PostgreSQL',
  sEParamRows: 'rows_from', sEParamRowsDesc: 'Chave do estado que contém a lista de linhas a inserir',
  sEParamCols: 'columns', sEParamColsDesc: 'Colunas a extrair de cada linha, em ordem, separadas por vírgula',
  sEParamParams: 'params', sEParamParamsDesc: 'Parâmetros estáticos adicionais (CSV)',
  sPxTitle: 'parseXml', sPxDesc: 'Lê um arquivo XML e extrai uma lista de elementos, salvando-a no estado.',
  sPxParamPath: 'path', sPxParamPathDesc: 'Caminho do arquivo XML (use isto ou file_key)',
  sPxParamKey: 'file_key', sPxParamKeyDesc: 'Chave do estado que contém o caminho do arquivo',
  sPxParamRoot: 'root_element', sPxParamRootDesc: 'Nome da tag a extrair (ex.: "product")',
  sPxParamRes: 'result_key', sPxParamResDesc: 'Chave onde a lista será salva',
  sWxTitle: 'writeXml', sWxDesc: 'Serializa uma lista do estado em um arquivo XML.',
  sWxParamData: 'data_key', sWxParamDataDesc: 'Chave do estado com a lista a serializar',
  sWxParamPath: 'path', sWxParamPathDesc: 'Caminho do arquivo de saída',
  sWxParamRoot: 'root_element', sWxParamRootDesc: 'Tag raiz do XML gerado',
  sWxParamRow: 'row_element', sWxParamRowDesc: 'Tag de cada item',
  sPjTitle: 'parseJson', sPjDesc: 'Lê um arquivo JSON e extrai dados para o estado. Suporta navegação em objetos aninhados via root_path.',
  sPjParamPath: 'path', sPjParamPathDesc: 'Caminho do arquivo JSON (use isto ou file_key)',
  sPjParamKey: 'file_key', sPjParamKeyDesc: 'Chave do estado que contém o caminho',
  sPjParamRoot: 'root_path', sPjParamRootDesc: 'Caminho com pontos para navegar no JSON (ex.: "catalog.items")',
  sPjParamRes: 'result_key', sPjParamResDesc: 'Chave onde os dados serão salvos',
  sPjStructNote: 'O arquivo JSON acima pode ter a estrutura:',
  sWjTitle: 'writeJson', sWjDesc: 'Serializa dados do estado em um arquivo JSON.',
  sWjParamData: 'data_key', sWjParamDataDesc: 'Chave do estado a serializar',
  sWjParamPath: 'path', sWjParamPathDesc: 'Caminho do arquivo de saída',
  sWjParamPretty: 'pretty', sWjParamPrettyDesc: 'Formata o JSON com indentação',
  cronTitle: 'Agendamento (Cron)',
  cronLead: 'Jobs podem ser agendados usando expressões cron de 5 campos:',
  cronNote: 'Deixe o campo vazio para que o job seja apenas manual. O construtor de agendamento na interface ajuda a montar a expressão visualmente.',
  cronEveryMin: 'Todo minuto', cronEveryHour: 'A cada hora (no minuto 0)', cronEveryDay: 'Todo dia às 09:00',
  cronWeekday: 'Todo dia de semana às 09:00', cronWeekdays: 'Segunda a sexta às 09:00',
  cronMonthly: 'Dia 1 de cada mês às 18:30', cronEvery4h: 'A cada 4 horas', cronEvery15m: 'A cada 15 minutos',
  dsTitle: 'Fontes de Dados',
  dsLead: 'Conexões de banco de dados são configuradas centralmente pelo administrador em <strong>Admin → Fontes de Dados</strong> e associadas a projetos. Os steps <code>queryDatabase</code> e <code>executeDatabase</code> referenciam a fonte pelo seu <strong>slug</strong>.',
  dsNote: 'Senhas de conexão são armazenadas criptografadas (AES-256-GCM). Nunca ficam expostas nos logs ou na interface.',
  dsTestNote: 'Para testar a conectividade sem executar um job, use o botão <strong>Testar conexão</strong> na tela de administração da fonte de dados.',
  dsMysqlLabel: 'Parâmetros bind:', dsPostgresLabel: 'Parâmetros bind:',
  relTitle: 'Janela de Execução',
  relLead: 'Cada job pode ter uma janela de validade com dois campos opcionais:',
  relFieldRelease: 'Disponível a partir de (release_at)', relDescRelease: 'O job fica em estado agendado até essa data/hora. Execuções manuais antes da janela são bloqueadas.',
  relFieldArchive: 'Expira em (archive_at)', relDescArchive: 'Após essa data/hora o job é arquivado automaticamente e não pode mais ser executado.',
  relNote: 'Ambos os campos são opcionais. Sem janela definida, o job pode ser executado a qualquer momento.',
  thParam: 'Parâmetro', thType: 'Tipo', thDefault: 'Padrão', thDesc: 'Descrição',
  thLevel: 'Nível', thValue: 'Valor', thCan: 'Pode fazer',
  thField: 'Campo', thBehavior: 'Comportamento',
  thExpr: 'Expressão', thMeaning: 'Significado',
  orManual: 'Ou insira a chave manualmente:',
  endNote: 'Fim da documentação —', endLink: 'criar um job agora',
  codeBasic: `meuJob {
  step "primeiroStep" {
    parametro1 "valor"
    parametro2 true
    parametro3 42
  },
  step "segundoStep" {
    chave "outro-valor"
  },
}`,
  codeUse: `importarEProcessar {
  use "processar-faturas-Ab3Kx9wZ",
  step "writeOutput" {
    path "data/saida"
  },
}`,
  codeReadDir: `processarArquivos {
  step "readDirectory" {
    path "data/entrada"
  },
}`,
  codeFilter: `processarCsv {
  step "readDirectory" {
    path "data/uploads"
  },
  step "filter" {
    extension "csv"
  },
}`,
  codeTransform: `normalizarTextos {
  step "readDirectory" { path "data/textos" },
  step "filter" { extension "txt" },
  step "transform" { operation "uppercase" },
}`,
  codeValidate: `importarClientes {
  step "parseJson" {
    path       "data/clientes.json"
    result_key "clientes"
  },
  step "validate" {
    email    "clientes.email"
    cpf      "clientes.cpf"
    telefone "clientes.fone"
    cep      "clientes.endereco.cep"
    regex    "clientes.codigo"
    pattern  "^CLI-[0-9]+$"
  },
  step "writeJson" {
    data_key "clientes"
    path     "data/saida/clientes.json"
  },
}`,
  codeWriteOutput: `exportarArquivos {
  step "readDirectory" { path "data/entrada" },
  step "filter" { extension "txt" },
  step "transform" { operation "lowercase" },
  step "writeOutput" { path "data/saida" },
}`,
  codeQueryDb: `exportarProdutos {
  step "queryDatabase" {
    source     "mysql-local"
    query      "SELECT id, nome, preco FROM produtos WHERE ativo = 1"
    result_key "produtos"
  },
  step "writeJson" {
    data_key "produtos"
    path     "data/saida/produtos.json"
    pretty   true
  },
}`,
  codeExecDb: `importarCatalogo {
  step "parseJson" {
    path       "data/sample/catalog.json"
    root_path  "catalog.items"
    result_key "itens"
  },
  step "executeDatabase" {
    source    "mysql-local"
    query     "INSERT INTO itens_importados (nome, categoria, preco) VALUES (?, ?, ?)"
    rows_from "itens"
    columns   "name,category,price"
  },
}`,
  codeParseXml: `lerCatalogoXml {
  step "parseXml" {
    path         "data/sample/catalog.xml"
    root_element "product"
    result_key   "produtos"
  },
}`,
  codeWriteXml: `exportarXml {
  step "queryDatabase" {
    source     "mysql-local"
    query      "SELECT nome, categoria, preco FROM produtos"
    result_key "produtos"
  },
  step "writeXml" {
    data_key     "produtos"
    path         "data/saida/produtos.xml"
    root_element "catalogo"
    row_element  "produto"
  },
}`,
  codeParseJson: `lerCatalogoJson {
  step "parseJson" {
    path       "data/sample/catalog.json"
    root_path  "catalog.items"
    result_key "itens"
  },
}`,
  codeJsonStruct: `{
  "catalog": {
    "version": "1.0",
    "items": [
      { "name": "Produto A", "category": "Cat1", "price": "10.00" }
    ]
  }
}`,
  codeWriteJson: `exportarJson {
  step "queryDatabase" {
    source     "mysql-local"
    query      "SELECT * FROM produtos WHERE ativo = 1"
    result_key "produtos"
  },
  step "writeJson" {
    data_key "produtos"
    path     "data/saida/produtos.json"
    pretty   true
  },
}`,
};

const EN: DocsContent = {
  toc: {
    intro: 'Introduction', concepts: 'Concepts', groups: 'Groups & Projects',
    jobs: 'Jobs', access: 'Access Levels', dsl: 'DSL — Syntax',
    'dsl-basic': 'Basic structure', 'dsl-values': 'Value types',
    'dsl-use': 'Job references', steps: 'Available steps',
    's-readdir': 'readDirectory', 's-filter': 'filter', 's-transform': 'transform',
    's-validate': 'validate',
    's-write': 'writeOutput', 's-qdb': 'queryDatabase', 's-edb': 'executeDatabase',
    's-pxml': 'parseXml', 's-wxml': 'writeXml', 's-pjson': 'parseJson', 's-wjson': 'writeJson',
    cron: 'Scheduling (Cron)', datasources: 'Data Sources', release: 'Execution Window',
  },
  introTitle: 'Cartograph — Documentation',
  introLead: 'Cartograph is a distributed task runner. You describe <strong>jobs</strong> using a simple DSL, group them into <strong>projects</strong>, and run them manually or on a cron schedule. Every execution is tracked with detailed real-time logs.',
  introTip: '<strong>Quick start:</strong> create a group → create a project inside it → add a job with the DSL → click <em>Run</em>.',
  conceptsTitle: 'Concepts',
  groupsTitle: 'Groups & Projects',
  groupsLead: 'The organisation hierarchy is:',
  groupLabelGroup: 'Group', groupDescGroup: '— groups related projects (e.g. "Backend", "Integrations")',
  groupLabelProject: 'Project', groupDescProject: '— contains jobs and members with their own permissions',
  groupLabelJob: 'Job (Task)', groupDescJob: '— executable unit, defined by the DSL',
  groupsNote: 'Projects inherit members from the parent group, but can have additional members with different access levels.',
  jobsTitle: 'Jobs',
  jobsLead: 'A job has:',
  jobFieldName: 'name', jobDescName: 'Human-readable name shown in the interface',
  jobFieldSlug: 'identifier', jobDescSlug: 'Unique slug within the project (kebab-case)',
  jobFieldId: 'Global ID', jobDescId: 'Auto-generated (identifier-XXXXXXXX). Used in cross-job references with use',
  jobFieldDsl: 'DSL', jobDescDsl: 'Code defining the steps to execute',
  jobFieldCron: 'Schedule', jobDescCron: 'Optional cron expression for automatic execution',
  jobFieldWin: 'Window', jobDescWin: 'Period in which the job can run (release / archive)',
  jobsNote: 'Each run produces an <strong>execution record</strong> with status, logs and duration. History is available in the <em>History</em> tab of the job edit screen.',
  accessTitle: 'Access Levels',
  accessLead: 'Cartograph uses a cascading permission system:',
  accessW: 'Wayfarer', accessWDesc: 'View projects and executions',
  accessE: 'Explorer', accessEDesc: '+ Run jobs manually',
  accessN: 'Navigator', accessNDesc: '+ Create and edit jobs, manage members',
  accessC: 'Cartographer', accessCDesc: 'Full access, including deletion and system administration',
  accessNote: 'Permissions on <strong>groups</strong> propagate to all child projects. Direct permissions on a project override those inherited from the group.',
  dslTitle: 'DSL — Syntax', dslLead: "Cartograph's DSL (Domain Specific Language) describes a job's pipeline as an ordered sequence of named steps.",
  dslBasicTitle: 'Basic structure',
  dslBasicLead: 'Each job has a root block with an <strong>identifier</strong> followed by <code>{}</code>. Inside it, one or more <code>step</code>s separated by commas:',
  dslBasicNote1: 'The root block identifier uses <strong>camelCase</strong> or <strong>snake_case</strong> (no hyphens)',
  dslBasicNote2: 'Steps are separated by <strong>commas</strong> — except the last one',
  dslBasicNote3: 'The step name is a string with the step type',
  dslBasicNote4: 'Each step runs in order and can pass data to the next via <strong>shared state</strong>',
  dslWarnTitle: 'Warning', dslWarnBody: 'Identifiers <strong>do not accept hyphens</strong>. Use <code>importData</code> instead of <code>import-data</code>.',
  dslValTitle: 'Value types',
  dslValStr: 'String', dslValStrNote: 'Always in double quotes',
  dslValInt: 'Integer', dslValIntNote: 'No quotes',
  dslValFloat: 'Decimal', dslValFloatNote: 'Dot as separator',
  dslValBool: 'Boolean', dslValBoolNote: 'Lowercase',
  dslValWarn: 'Literal lists are <strong>not supported</strong>. To pass multiple values use a CSV string: <code>columns "name,category,price"</code>',
  dslUseTitle: 'Cross-job references (use)',
  dslUseLead: 'A job can depend on another by using the <strong>global ID</strong> of the referenced job. The global ID appears on the job edit screen.',
  dslUseNote: 'References create a dependency graph. Cartograph detects cycles and prevents infinite executions. Visualise the flow of a job in the <em>Flow</em> tab.',
  stepsTitle: 'Available steps',
  stepsLead: 'Each step receives parameters and operates on the <strong>shared execution state</strong> — a key/value map that persists between steps.',
  sRdTitle: 'readDirectory', sRdDesc: 'Reads the files in a directory and stores the list in state. Used as the entry point for file-processing pipelines.',
  sRdParamPath: 'path', sRdParamPathDesc: 'Directory to read (relative to the application root)',
  sFTitle: 'filter', sFDesc: 'Filters the file list in state by extension. Usually used after readDirectory.',
  sFParamExt: 'extension', sFParamExtDesc: 'Extension without dot (e.g. "csv", "xml")',
  sTTitle: 'transform', sTDesc: 'Applies a text transformation to the content of files in memory.',
  sTParamOp: 'operation', sTParamOpDesc: '"uppercase" or "lowercase"',
  sVTitle: 'validate', sVDesc: 'Validates the format of state fields, Bean Validation style: each parameter is a validator pointing at a field (dot path; lists validate every element). Any violation stops the job, listing all invalid values.',
  sVParamEmail: 'email', sVParamEmailDesc: 'State field holding the email(s) to validate (e.g. "rows.email")',
  sVParamCpf: 'cpf', sVParamCpfDesc: 'Field holding CPF(s) — accepts "529.982.247-25" or bare digits; verifies the check digits',
  sVParamCnpj: 'cnpj', sVParamCnpjDesc: 'Field holding CNPJ(s) — numeric or alphanumeric (2026 format, e.g. "12.ABC.345/01DE-35"); verifies the check digits',
  sVParamTel: 'telefone', sVParamTelDesc: 'Field holding Brazilian phone number(s) — area code + 9-digit mobile or 8-digit landline, with or without +55 and formatting',
  sVParamCep: 'cep', sVParamCepDesc: 'Field holding CEP(s) — 8 digits, optional hyphen (e.g. "01310-100")',
  sVParamRegex: 'regex', sVParamRegexDesc: 'Field to validate against a custom regular expression (requires the pattern param)',
  sVParamPattern: 'pattern', sVParamPatternDesc: 'The regular expression used by the regex validator (e.g. "^[A-Z]{3}-[0-9]+$"; write \\\\d for \\d)',
  sVNote: 'Use at least one validator. A value matching no state field is validated as a literal (e.g. email "teste@example.com"); when the field exists it takes precedence, and a missing field inside a list counts as a violation — the step acts as a quality gate before writing or exporting data.',
  sWoTitle: 'writeOutput', sWoDesc: 'Writes the processed files from state to an output directory.',
  sWoParamPath: 'path', sWoParamPathDesc: 'Destination directory',
  sQTitle: 'queryDatabase', sQDesc: 'Executes a SELECT query on a data source and saves the results to state. The source must be configured by an admin and associated with the project.',
  sQParamSrc: 'source', sQParamSrcDesc: 'Data source slug (e.g. "mysql-local")',
  sQParamQuery: 'query', sQParamQueryDesc: 'SQL query to execute',
  sQParamKey: 'result_key', sQParamKeyDesc: 'State key where results will be saved',
  sQParamParams: 'params', sQParamParamsDesc: 'Comma-separated bind parameters (SQL Injection prevention)',
  sETitle: 'executeDatabase', sEDesc: 'Executes an INSERT, UPDATE or DELETE query for each row of a list in state.',
  sEParamSrc: 'source', sEParamSrcDesc: 'Data source slug',
  sEParamQuery: 'query', sEParamQueryDesc: 'Parameterised query with ? for MySQL or $1,$2 for PostgreSQL',
  sEParamRows: 'rows_from', sEParamRowsDesc: 'State key containing the list of rows to insert',
  sEParamCols: 'columns', sEParamColsDesc: 'Columns to extract from each row, in order, comma-separated',
  sEParamParams: 'params', sEParamParamsDesc: 'Additional static parameters (CSV)',
  sPxTitle: 'parseXml', sPxDesc: 'Reads an XML file and extracts a list of elements, saving it to state.',
  sPxParamPath: 'path', sPxParamPathDesc: 'XML file path (use this or file_key)',
  sPxParamKey: 'file_key', sPxParamKeyDesc: 'State key containing the file path',
  sPxParamRoot: 'root_element', sPxParamRootDesc: 'Tag name to extract (e.g. "product")',
  sPxParamRes: 'result_key', sPxParamResDesc: 'Key where the list will be saved',
  sWxTitle: 'writeXml', sWxDesc: 'Serialises a list from state into an XML file.',
  sWxParamData: 'data_key', sWxParamDataDesc: 'State key with the list to serialise',
  sWxParamPath: 'path', sWxParamPathDesc: 'Output file path',
  sWxParamRoot: 'root_element', sWxParamRootDesc: 'Root tag of the generated XML',
  sWxParamRow: 'row_element', sWxParamRowDesc: 'Tag for each item',
  sPjTitle: 'parseJson', sPjDesc: 'Reads a JSON file and extracts data into state. Supports navigation into nested objects via root_path.',
  sPjParamPath: 'path', sPjParamPathDesc: 'JSON file path (use this or file_key)',
  sPjParamKey: 'file_key', sPjParamKeyDesc: 'State key containing the file path',
  sPjParamRoot: 'root_path', sPjParamRootDesc: 'Dot-separated path to navigate the JSON (e.g. "catalog.items")',
  sPjParamRes: 'result_key', sPjParamResDesc: 'Key where data will be saved',
  sPjStructNote: 'The JSON file above may have the structure:',
  sWjTitle: 'writeJson', sWjDesc: 'Serialises data from state into a JSON file.',
  sWjParamData: 'data_key', sWjParamDataDesc: 'State key to serialise',
  sWjParamPath: 'path', sWjParamPathDesc: 'Output file path',
  sWjParamPretty: 'pretty', sWjParamPrettyDesc: 'Format JSON with indentation',
  cronTitle: 'Scheduling (Cron)',
  cronLead: 'Jobs can be scheduled using 5-field cron expressions:',
  cronNote: 'Leave the field empty to make the job manual-only. The schedule builder in the interface helps compose the expression visually.',
  cronEveryMin: 'Every minute', cronEveryHour: 'Every hour (at minute 0)', cronEveryDay: 'Every day at 09:00',
  cronWeekday: 'Every weekday at 09:00', cronWeekdays: 'Monday to Friday at 09:00',
  cronMonthly: '1st of every month at 18:30', cronEvery4h: 'Every 4 hours', cronEvery15m: 'Every 15 minutes',
  dsTitle: 'Data Sources',
  dsLead: 'Database connections are centrally configured by an admin under <strong>Admin → Data Sources</strong> and associated with projects. The <code>queryDatabase</code> and <code>executeDatabase</code> steps reference the source by its <strong>slug</strong>.',
  dsNote: 'Connection passwords are stored encrypted (AES-256-GCM). They are never exposed in logs or the interface.',
  dsTestNote: 'To test connectivity without running a job, use the <strong>Test connection</strong> button on the data source admin screen.',
  dsMysqlLabel: 'Bind parameters:', dsPostgresLabel: 'Bind parameters:',
  relTitle: 'Execution Window',
  relLead: 'Each job can have a validity window with two optional fields:',
  relFieldRelease: 'Available from (release_at)', relDescRelease: 'The job stays in scheduled state until this date/time. Manual runs before the window are blocked.',
  relFieldArchive: 'Expires at (archive_at)', relDescArchive: 'After this date/time the job is automatically archived and can no longer be executed.',
  relNote: 'Both fields are optional. Without a defined window, the job can run at any time.',
  thParam: 'Parameter', thType: 'Type', thDefault: 'Default', thDesc: 'Description',
  thLevel: 'Level', thValue: 'Value', thCan: 'Can do',
  thField: 'Field', thBehavior: 'Behaviour',
  thExpr: 'Expression', thMeaning: 'Meaning',
  orManual: 'Or enter the key manually:',
  endNote: 'End of documentation —', endLink: 'create a job now',
  codeBasic: `myJob {
  step "firstStep" {
    param1 "value"
    param2 true
    param3 42
  },
  step "secondStep" {
    key "another-value"
  },
}`,
  codeUse: `importAndProcess {
  use "process-invoices-Ab3Kx9wZ",
  step "writeOutput" {
    path "data/output"
  },
}`,
  codeReadDir: `processFiles {
  step "readDirectory" {
    path "data/inbox"
  },
}`,
  codeFilter: `processCsvFiles {
  step "readDirectory" {
    path "data/uploads"
  },
  step "filter" {
    extension "csv"
  },
}`,
  codeTransform: `normalizeTexts {
  step "readDirectory" { path "data/texts" },
  step "filter" { extension "txt" },
  step "transform" { operation "uppercase" },
}`,
  codeValidate: `importCustomers {
  step "parseJson" {
    path       "data/customers.json"
    result_key "customers"
  },
  step "validate" {
    email    "customers.email"
    cpf      "customers.cpf"
    telefone "customers.phone"
    cep      "customers.address.cep"
    regex    "customers.code"
    pattern  "^CLI-[0-9]+$"
  },
  step "writeJson" {
    data_key "customers"
    path     "data/output/customers.json"
  },
}`,
  codeWriteOutput: `exportFiles {
  step "readDirectory" { path "data/inbox" },
  step "filter" { extension "txt" },
  step "transform" { operation "lowercase" },
  step "writeOutput" { path "data/outbox" },
}`,
  codeQueryDb: `exportProducts {
  step "queryDatabase" {
    source     "mysql-local"
    query      "SELECT id, name, price FROM products WHERE active = 1"
    result_key "products"
  },
  step "writeJson" {
    data_key "products"
    path     "data/output/products.json"
    pretty   true
  },
}`,
  codeExecDb: `importCatalog {
  step "parseJson" {
    path       "data/sample/catalog.json"
    root_path  "catalog.items"
    result_key "items"
  },
  step "executeDatabase" {
    source    "mysql-local"
    query     "INSERT INTO imported_items (name, category, price) VALUES (?, ?, ?)"
    rows_from "items"
    columns   "name,category,price"
  },
}`,
  codeParseXml: `readCatalogXml {
  step "parseXml" {
    path         "data/sample/catalog.xml"
    root_element "product"
    result_key   "products"
  },
}`,
  codeWriteXml: `exportXml {
  step "queryDatabase" {
    source     "mysql-local"
    query      "SELECT name, category, price FROM products"
    result_key "products"
  },
  step "writeXml" {
    data_key     "products"
    path         "data/output/products.xml"
    root_element "catalog"
    row_element  "product"
  },
}`,
  codeParseJson: `readCatalogJson {
  step "parseJson" {
    path       "data/sample/catalog.json"
    root_path  "catalog.items"
    result_key "items"
  },
}`,
  codeJsonStruct: `{
  "catalog": {
    "version": "1.0",
    "items": [
      { "name": "Product A", "category": "Cat1", "price": "10.00" }
    ]
  }
}`,
  codeWriteJson: `exportJson {
  step "queryDatabase" {
    source     "mysql-local"
    query      "SELECT * FROM products WHERE active = 1"
    result_key "products"
  },
  step "writeJson" {
    data_key "products"
    path     "data/output/products.json"
    pretty   true
  },
}`,
};

// ── TOC structure (ids are language-independent) ──────────────────────────────

const TOC_STRUCTURE: Array<{ id: string; children?: Array<{ id: string }> }> = [
  { id: 'intro' },
  { id: 'concepts', children: [{ id: 'groups' }, { id: 'jobs' }, { id: 'access' }] },
  { id: 'dsl', children: [{ id: 'dsl-basic' }, { id: 'dsl-values' }, { id: 'dsl-use' }] },
  { id: 'steps', children: [
    { id: 's-readdir' }, { id: 's-filter' }, { id: 's-transform' }, { id: 's-validate' }, { id: 's-write' },
    { id: 's-qdb' }, { id: 's-edb' }, { id: 's-pxml' }, { id: 's-wxml' },
    { id: 's-pjson' }, { id: 's-wjson' },
  ]},
  { id: 'cron' },
  { id: 'datasources' },
  { id: 'release' },
];

@Component({
  selector: 'app-docs',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CommonModule, IconComponent, RouterModule],
  template: `
    <div class="docs-layout">

      <!-- Sidebar TOC -->
      <nav class="docs-toc" aria-label="Index">
        <div class="toc-title">
          <app-icon>menu_book</app-icon>
          {{ c().toc['intro'] ? 'Docs' : 'Docs' }}
        </div>
        <ul class="toc-list">
          <ng-container *ngFor="let s of tocStructure">
            <li>
              <a class="toc-link" [class.active]="active === s.id" (click)="scrollTo(s.id)">{{ c().toc[s.id] }}</a>
              <ul *ngIf="s.children" class="toc-sub">
                <li *ngFor="let child of s.children">
                  <a class="toc-link toc-sub-link" [class.active]="active === child.id" (click)="scrollTo(child.id)">{{ c().toc[child.id] }}</a>
                </li>
              </ul>
            </li>
          </ng-container>
        </ul>
      </nav>

      <!-- Main content -->
      <article class="docs-content">

        <!-- INTRO -->
        <section id="intro" class="doc-section">
          <h1 class="doc-h1"><app-icon class="h-icon">map</app-icon>{{ c().introTitle }}</h1>
          <p class="doc-lead" [innerHTML]="c().introLead"></p>
          <div class="info-box"><app-icon>lightbulb</app-icon><div [innerHTML]="c().introTip"></div></div>
        </section>

        <!-- CONCEPTS -->
        <section id="concepts" class="doc-section">
          <h2 class="doc-h2">{{ c().conceptsTitle }}</h2>
        </section>

        <section id="groups" class="doc-section">
          <h3 class="doc-h3">{{ c().groupsTitle }}</h3>
          <p>{{ c().groupsLead }}</p>
          <div class="hierarchy">
            <div class="h-item"><app-icon>folder</app-icon><strong>{{ c().groupLabelGroup }}</strong><span>{{ c().groupDescGroup }}</span></div>
            <div class="h-arrow">↓</div>
            <div class="h-item"><app-icon>work</app-icon><strong>{{ c().groupLabelProject }}</strong><span>{{ c().groupDescProject }}</span></div>
            <div class="h-arrow">↓</div>
            <div class="h-item"><app-icon>bolt</app-icon><strong>{{ c().groupLabelJob }}</strong><span>{{ c().groupDescJob }}</span></div>
          </div>
          <p>{{ c().groupsNote }}</p>
        </section>

        <section id="jobs" class="doc-section">
          <h3 class="doc-h3">{{ c().jobsTitle }}</h3>
          <p>{{ c().jobsLead }}</p>
          <table class="doc-table">
            <thead><tr><th>{{ c().thField }}</th><th>{{ c().thDesc }}</th></tr></thead>
            <tbody>
              <tr><td><code>{{ c().jobFieldName }}</code></td><td>{{ c().jobDescName }}</td></tr>
              <tr><td><code>{{ c().jobFieldSlug }}</code></td><td>{{ c().jobDescSlug }}</td></tr>
              <tr><td><code>{{ c().jobFieldId }}</code></td><td>{{ c().jobDescId }}</td></tr>
              <tr><td><code>{{ c().jobFieldDsl }}</code></td><td>{{ c().jobDescDsl }}</td></tr>
              <tr><td><code>{{ c().jobFieldCron }}</code></td><td>{{ c().jobDescCron }}</td></tr>
              <tr><td><code>{{ c().jobFieldWin }}</code></td><td>{{ c().jobDescWin }}</td></tr>
            </tbody>
          </table>
          <p [innerHTML]="c().jobsNote"></p>
        </section>

        <section id="access" class="doc-section">
          <h3 class="doc-h3">{{ c().accessTitle }}</h3>
          <p>{{ c().accessLead }}</p>
          <table class="doc-table">
            <thead><tr><th>{{ c().thLevel }}</th><th>{{ c().thValue }}</th><th>{{ c().thCan }}</th></tr></thead>
            <tbody>
              <tr><td><span class="badge wayfarer">{{ c().accessW }}</span></td><td>10</td><td>{{ c().accessWDesc }}</td></tr>
              <tr><td><span class="badge explorer">{{ c().accessE }}</span></td><td>20</td><td>{{ c().accessEDesc }}</td></tr>
              <tr><td><span class="badge navigator">{{ c().accessN }}</span></td><td>30</td><td>{{ c().accessNDesc }}</td></tr>
              <tr><td><span class="badge cartographer">{{ c().accessC }}</span></td><td>40</td><td>{{ c().accessCDesc }}</td></tr>
            </tbody>
          </table>
          <div class="info-box"><app-icon>info</app-icon><div [innerHTML]="c().accessNote"></div></div>
        </section>

        <!-- DSL -->
        <section id="dsl" class="doc-section">
          <h2 class="doc-h2">{{ c().dslTitle }}</h2>
          <p>{{ c().dslLead }}</p>
        </section>

        <section id="dsl-basic" class="doc-section">
          <h3 class="doc-h3">{{ c().dslBasicTitle }}</h3>
          <p [innerHTML]="c().dslBasicLead"></p>
          <pre class="code-block">{{ c().codeBasic }}</pre>
          <ul class="doc-list">
            <li [innerHTML]="c().dslBasicNote1"></li>
            <li [innerHTML]="c().dslBasicNote2"></li>
            <li>{{ c().dslBasicNote3 }}</li>
            <li [innerHTML]="c().dslBasicNote4"></li>
          </ul>
          <div class="info-box warn"><app-icon>warning</app-icon><div [innerHTML]="c().dslWarnBody"></div></div>
        </section>

        <section id="dsl-values" class="doc-section">
          <h3 class="doc-h3">{{ c().dslValTitle }}</h3>
          <table class="doc-table">
            <thead><tr><th>{{ c().thType }}</th><th>{{ c().thDesc }}</th><th>{{ c().thDefault }}</th></tr></thead>
            <tbody>
              <tr><td>{{ c().dslValStr }}</td><td><code>"texto aqui"</code></td><td>{{ c().dslValStrNote }}</td></tr>
              <tr><td>{{ c().dslValInt }}</td><td><code>42</code></td><td>{{ c().dslValIntNote }}</td></tr>
              <tr><td>{{ c().dslValFloat }}</td><td><code>3.14</code></td><td>{{ c().dslValFloatNote }}</td></tr>
              <tr><td>{{ c().dslValBool }}</td><td><code>true</code> / <code>false</code></td><td>{{ c().dslValBoolNote }}</td></tr>
            </tbody>
          </table>
          <div class="info-box warn"><app-icon>warning</app-icon><div [innerHTML]="c().dslValWarn"></div></div>
        </section>

        <section id="dsl-use" class="doc-section">
          <h3 class="doc-h3">{{ c().dslUseTitle }}</h3>
          <p [innerHTML]="c().dslUseLead"></p>
          <pre class="code-block">{{ c().codeUse }}</pre>
          <div class="info-box"><app-icon>account_tree</app-icon><div [innerHTML]="c().dslUseNote"></div></div>
        </section>

        <!-- STEPS -->
        <section id="steps" class="doc-section">
          <h2 class="doc-h2">{{ c().stepsTitle }}</h2>
          <p [innerHTML]="c().stepsLead"></p>
        </section>

        <section id="s-readdir" class="doc-section">
          <h3 class="doc-h3"><span class="step-badge">{{ c().sRdTitle }}</span></h3>
          <p>{{ c().sRdDesc }}</p>
          <table class="doc-table">
            <thead><tr><th>{{ c().thParam }}</th><th>{{ c().thType }}</th><th>{{ c().thDefault }}</th><th>{{ c().thDesc }}</th></tr></thead>
            <tbody><tr><td><code>{{ c().sRdParamPath }}</code></td><td>string</td><td><code>"data/inbox"</code></td><td>{{ c().sRdParamPathDesc }}</td></tr></tbody>
          </table>
          <pre class="code-block">{{ c().codeReadDir }}</pre>
        </section>

        <section id="s-filter" class="doc-section">
          <h3 class="doc-h3"><span class="step-badge">{{ c().sFTitle }}</span></h3>
          <p>{{ c().sFDesc }}</p>
          <table class="doc-table">
            <thead><tr><th>{{ c().thParam }}</th><th>{{ c().thType }}</th><th>{{ c().thDefault }}</th><th>{{ c().thDesc }}</th></tr></thead>
            <tbody><tr><td><code>{{ c().sFParamExt }}</code></td><td>string</td><td><code>"txt"</code></td><td>{{ c().sFParamExtDesc }}</td></tr></tbody>
          </table>
          <pre class="code-block">{{ c().codeFilter }}</pre>
        </section>

        <section id="s-transform" class="doc-section">
          <h3 class="doc-h3"><span class="step-badge">{{ c().sTTitle }}</span></h3>
          <p>{{ c().sTDesc }}</p>
          <table class="doc-table">
            <thead><tr><th>{{ c().thParam }}</th><th>{{ c().thType }}</th><th>{{ c().thDefault }}</th><th>{{ c().thDesc }}</th></tr></thead>
            <tbody><tr><td><code>{{ c().sTParamOp }}</code></td><td>string</td><td><code>"uppercase"</code></td><td>{{ c().sTParamOpDesc }}</td></tr></tbody>
          </table>
          <pre class="code-block">{{ c().codeTransform }}</pre>
        </section>

        <section id="s-validate" class="doc-section">
          <h3 class="doc-h3"><span class="step-badge">{{ c().sVTitle }}</span></h3>
          <p>{{ c().sVDesc }}</p>
          <table class="doc-table">
            <thead><tr><th>{{ c().thParam }}</th><th>{{ c().thType }}</th><th>{{ c().thDefault }}</th><th>{{ c().thDesc }}</th></tr></thead>
            <tbody>
              <tr><td><code>{{ c().sVParamEmail }}</code></td><td>string</td><td>—</td><td>{{ c().sVParamEmailDesc }}</td></tr>
              <tr><td><code>{{ c().sVParamCpf }}</code></td><td>string</td><td>—</td><td>{{ c().sVParamCpfDesc }}</td></tr>
              <tr><td><code>{{ c().sVParamCnpj }}</code></td><td>string</td><td>—</td><td>{{ c().sVParamCnpjDesc }}</td></tr>
              <tr><td><code>{{ c().sVParamTel }}</code></td><td>string</td><td>—</td><td>{{ c().sVParamTelDesc }}</td></tr>
              <tr><td><code>{{ c().sVParamCep }}</code></td><td>string</td><td>—</td><td>{{ c().sVParamCepDesc }}</td></tr>
              <tr><td><code>{{ c().sVParamRegex }}</code></td><td>string</td><td>—</td><td>{{ c().sVParamRegexDesc }}</td></tr>
              <tr><td><code>{{ c().sVParamPattern }}</code></td><td>string</td><td>—</td><td>{{ c().sVParamPatternDesc }}</td></tr>
            </tbody>
          </table>
          <p>{{ c().sVNote }}</p>
          <pre class="code-block">{{ c().codeValidate }}</pre>
        </section>

        <section id="s-write" class="doc-section">
          <h3 class="doc-h3"><span class="step-badge">{{ c().sWoTitle }}</span></h3>
          <p>{{ c().sWoDesc }}</p>
          <table class="doc-table">
            <thead><tr><th>{{ c().thParam }}</th><th>{{ c().thType }}</th><th>{{ c().thDefault }}</th><th>{{ c().thDesc }}</th></tr></thead>
            <tbody><tr><td><code>{{ c().sWoParamPath }}</code></td><td>string</td><td><code>"data/outbox"</code></td><td>{{ c().sWoParamPathDesc }}</td></tr></tbody>
          </table>
          <pre class="code-block">{{ c().codeWriteOutput }}</pre>
        </section>

        <section id="s-qdb" class="doc-section">
          <h3 class="doc-h3"><span class="step-badge">{{ c().sQTitle }}</span></h3>
          <p>{{ c().sQDesc }}</p>
          <table class="doc-table">
            <thead><tr><th>{{ c().thParam }}</th><th>{{ c().thType }}</th><th>{{ c().thDefault }}</th><th>{{ c().thDesc }}</th></tr></thead>
            <tbody>
              <tr><td><code>{{ c().sQParamSrc }}</code></td><td>string</td><td>—</td><td>{{ c().sQParamSrcDesc }}</td></tr>
              <tr><td><code>{{ c().sQParamQuery }}</code></td><td>string</td><td>—</td><td>{{ c().sQParamQueryDesc }}</td></tr>
              <tr><td><code>{{ c().sQParamKey }}</code></td><td>string</td><td><code>"rows"</code></td><td>{{ c().sQParamKeyDesc }}</td></tr>
              <tr><td><code>{{ c().sQParamParams }}</code></td><td>string</td><td><code>""</code></td><td>{{ c().sQParamParamsDesc }}</td></tr>
            </tbody>
          </table>
          <pre class="code-block">{{ c().codeQueryDb }}</pre>
        </section>

        <section id="s-edb" class="doc-section">
          <h3 class="doc-h3"><span class="step-badge">{{ c().sETitle }}</span></h3>
          <p>{{ c().sEDesc }}</p>
          <table class="doc-table">
            <thead><tr><th>{{ c().thParam }}</th><th>{{ c().thType }}</th><th>{{ c().thDefault }}</th><th>{{ c().thDesc }}</th></tr></thead>
            <tbody>
              <tr><td><code>{{ c().sEParamSrc }}</code></td><td>string</td><td>—</td><td>{{ c().sEParamSrcDesc }}</td></tr>
              <tr><td><code>{{ c().sEParamQuery }}</code></td><td>string</td><td>—</td><td>{{ c().sEParamQueryDesc }}</td></tr>
              <tr><td><code>{{ c().sEParamRows }}</code></td><td>string</td><td>—</td><td>{{ c().sEParamRowsDesc }}</td></tr>
              <tr><td><code>{{ c().sEParamCols }}</code></td><td>string</td><td>—</td><td>{{ c().sEParamColsDesc }}</td></tr>
              <tr><td><code>{{ c().sEParamParams }}</code></td><td>string</td><td><code>""</code></td><td>{{ c().sEParamParamsDesc }}</td></tr>
            </tbody>
          </table>
          <pre class="code-block">{{ c().codeExecDb }}</pre>
        </section>

        <section id="s-pxml" class="doc-section">
          <h3 class="doc-h3"><span class="step-badge">{{ c().sPxTitle }}</span></h3>
          <p>{{ c().sPxDesc }}</p>
          <table class="doc-table">
            <thead><tr><th>{{ c().thParam }}</th><th>{{ c().thType }}</th><th>{{ c().thDefault }}</th><th>{{ c().thDesc }}</th></tr></thead>
            <tbody>
              <tr><td><code>{{ c().sPxParamPath }}</code></td><td>string</td><td>—</td><td>{{ c().sPxParamPathDesc }}</td></tr>
              <tr><td><code>{{ c().sPxParamKey }}</code></td><td>string</td><td><code>"current_file"</code></td><td>{{ c().sPxParamKeyDesc }}</td></tr>
              <tr><td><code>{{ c().sPxParamRoot }}</code></td><td>string</td><td>—</td><td>{{ c().sPxParamRootDesc }}</td></tr>
              <tr><td><code>{{ c().sPxParamRes }}</code></td><td>string</td><td><code>"rows"</code></td><td>{{ c().sPxParamResDesc }}</td></tr>
            </tbody>
          </table>
          <pre class="code-block">{{ c().codeParseXml }}</pre>
        </section>

        <section id="s-wxml" class="doc-section">
          <h3 class="doc-h3"><span class="step-badge">{{ c().sWxTitle }}</span></h3>
          <p>{{ c().sWxDesc }}</p>
          <table class="doc-table">
            <thead><tr><th>{{ c().thParam }}</th><th>{{ c().thType }}</th><th>{{ c().thDefault }}</th><th>{{ c().thDesc }}</th></tr></thead>
            <tbody>
              <tr><td><code>{{ c().sWxParamData }}</code></td><td>string</td><td><code>"rows"</code></td><td>{{ c().sWxParamDataDesc }}</td></tr>
              <tr><td><code>{{ c().sWxParamPath }}</code></td><td>string</td><td>—</td><td>{{ c().sWxParamPathDesc }}</td></tr>
              <tr><td><code>{{ c().sWxParamRoot }}</code></td><td>string</td><td><code>"rows"</code></td><td>{{ c().sWxParamRootDesc }}</td></tr>
              <tr><td><code>{{ c().sWxParamRow }}</code></td><td>string</td><td><code>"row"</code></td><td>{{ c().sWxParamRowDesc }}</td></tr>
            </tbody>
          </table>
          <pre class="code-block">{{ c().codeWriteXml }}</pre>
        </section>

        <section id="s-pjson" class="doc-section">
          <h3 class="doc-h3"><span class="step-badge">{{ c().sPjTitle }}</span></h3>
          <p>{{ c().sPjDesc }}</p>
          <table class="doc-table">
            <thead><tr><th>{{ c().thParam }}</th><th>{{ c().thType }}</th><th>{{ c().thDefault }}</th><th>{{ c().thDesc }}</th></tr></thead>
            <tbody>
              <tr><td><code>{{ c().sPjParamPath }}</code></td><td>string</td><td>—</td><td>{{ c().sPjParamPathDesc }}</td></tr>
              <tr><td><code>{{ c().sPjParamKey }}</code></td><td>string</td><td><code>"current_file"</code></td><td>{{ c().sPjParamKeyDesc }}</td></tr>
              <tr><td><code>{{ c().sPjParamRoot }}</code></td><td>string</td><td>—</td><td>{{ c().sPjParamRootDesc }}</td></tr>
              <tr><td><code>{{ c().sPjParamRes }}</code></td><td>string</td><td><code>"rows"</code></td><td>{{ c().sPjParamResDesc }}</td></tr>
            </tbody>
          </table>
          <pre class="code-block">{{ c().codeParseJson }}</pre>
          <p>{{ c().sPjStructNote }}</p>
          <pre class="code-block">{{ c().codeJsonStruct }}</pre>
        </section>

        <section id="s-wjson" class="doc-section">
          <h3 class="doc-h3"><span class="step-badge">{{ c().sWjTitle }}</span></h3>
          <p>{{ c().sWjDesc }}</p>
          <table class="doc-table">
            <thead><tr><th>{{ c().thParam }}</th><th>{{ c().thType }}</th><th>{{ c().thDefault }}</th><th>{{ c().thDesc }}</th></tr></thead>
            <tbody>
              <tr><td><code>{{ c().sWjParamData }}</code></td><td>string</td><td><code>"rows"</code></td><td>{{ c().sWjParamDataDesc }}</td></tr>
              <tr><td><code>{{ c().sWjParamPath }}</code></td><td>string</td><td>—</td><td>{{ c().sWjParamPathDesc }}</td></tr>
              <tr><td><code>{{ c().sWjParamPretty }}</code></td><td>boolean</td><td><code>false</code></td><td>{{ c().sWjParamPrettyDesc }}</td></tr>
            </tbody>
          </table>
          <pre class="code-block">{{ c().codeWriteJson }}</pre>
        </section>

        <!-- CRON -->
        <section id="cron" class="doc-section">
          <h2 class="doc-h2">{{ c().cronTitle }}</h2>
          <p>{{ c().cronLead }}</p>
          <pre class="code-block">┌──────────── {{ cronMin }}     (0–59)
│ ┌────────── {{ cronHour }}       (0–23)
│ │ ┌──────── {{ cronDay }}  (1–31)
│ │ │ ┌────── {{ cronMonth }}        (1–12)
│ │ │ │ ┌──── {{ cronWday }} (0–7)
│ │ │ │ │
* * * * *</pre>
          <table class="doc-table">
            <thead><tr><th>{{ c().thExpr }}</th><th>{{ c().thMeaning }}</th></tr></thead>
            <tbody>
              <tr><td><code>* * * * *</code></td><td>{{ c().cronEveryMin }}</td></tr>
              <tr><td><code>0 * * * *</code></td><td>{{ c().cronEveryHour }}</td></tr>
              <tr><td><code>0 9 * * *</code></td><td>{{ c().cronEveryDay }}</td></tr>
              <tr><td><code>0 9 * * 1</code></td><td>{{ c().cronWeekday }}</td></tr>
              <tr><td><code>0 9 * * 1-5</code></td><td>{{ c().cronWeekdays }}</td></tr>
              <tr><td><code>30 18 1 * *</code></td><td>{{ c().cronMonthly }}</td></tr>
              <tr><td><code>0 */4 * * *</code></td><td>{{ c().cronEvery4h }}</td></tr>
              <tr><td><code>*/15 * * * *</code></td><td>{{ c().cronEvery15m }}</td></tr>
            </tbody>
          </table>
          <p>{{ c().cronNote }}</p>
        </section>

        <!-- DATA SOURCES -->
        <section id="datasources" class="doc-section">
          <h2 class="doc-h2">{{ c().dsTitle }}</h2>
          <p [innerHTML]="c().dsLead"></p>
          <div class="steps-grid">
            <div class="step-card">
              <app-icon class="db-icon mysql">storage</app-icon>
              <strong>MySQL 8+</strong>
              <p>adapter: <code>mysql</code></p>
              <p>{{ c().dsMysqlLabel }} <code>?</code></p>
            </div>
            <div class="step-card">
              <app-icon class="db-icon postgres">storage</app-icon>
              <strong>PostgreSQL 14+</strong>
              <p>adapter: <code>postgres</code></p>
              <p>{{ c().dsPostgresLabel }} <code>$1, $2</code></p>
            </div>
          </div>
          <div class="info-box"><app-icon>lock</app-icon><div>{{ c().dsNote }}</div></div>
          <p [innerHTML]="c().dsTestNote"></p>
        </section>

        <!-- RELEASE WINDOW -->
        <section id="release" class="doc-section">
          <h2 class="doc-h2">{{ c().relTitle }}</h2>
          <p>{{ c().relLead }}</p>
          <table class="doc-table">
            <thead><tr><th>{{ c().thField }}</th><th>{{ c().thBehavior }}</th></tr></thead>
            <tbody>
              <tr><td><strong>{{ c().relFieldRelease }}</strong></td><td>{{ c().relDescRelease }}</td></tr>
              <tr><td><strong>{{ c().relFieldArchive }}</strong></td><td>{{ c().relDescArchive }}</td></tr>
            </tbody>
          </table>
          <p>{{ c().relNote }}</p>
          <div class="doc-end-mark">
            <app-icon>check_circle</app-icon>
            <span>{{ c().endNote }} <a routerLink="/tasks/new">{{ c().endLink }}</a></span>
          </div>
        </section>

      </article>
    </div>
  `,
  styles: [`
    :host { display: block; }
    .docs-layout { display: flex; gap: 0; max-width: 1200px; margin: 0 auto; padding: 24px 16px 80px; align-items: flex-start; }
    .docs-toc { position: sticky; top: 80px; width: 220px; flex-shrink: 0; margin-right: 40px; max-height: calc(100vh - 100px); overflow-y: auto; }
    .toc-title { display: flex; align-items: center; gap: 6px; font-size: 11px; font-weight: 700; letter-spacing: 1px; text-transform: uppercase; color: var(--cg-text-muted); margin-bottom: 12px; padding-bottom: 8px; border-bottom: 1px solid var(--cg-border); app-icon { font-size: 16px; width: 16px; height: 16px; } }
    .toc-list { list-style: none; margin: 0; padding: 0; }
    .toc-sub  { list-style: none; margin: 0; padding: 0 0 0 12px; }
    .toc-link { display: block; padding: 4px 8px; font-size: 13px; color: var(--cg-text-muted); border-radius: 4px; cursor: pointer; transition: color 0.15s, background 0.15s;
      &:hover { color: var(--cg-text); background: color-mix(in srgb, var(--cg-accent, #6366f1) 10%, transparent); }
      &.active { color: var(--cg-accent, #6366f1); background: color-mix(in srgb, var(--cg-accent, #6366f1) 12%, transparent); font-weight: 600; } }
    .toc-sub-link { font-size: 12px; padding: 3px 8px; }
    .docs-content { flex: 1; min-width: 0; }
    .doc-section { margin-bottom: 40px; scroll-margin-top: 80px; }
    .doc-h1 { font-size: 28px; font-weight: 800; color: var(--cg-text); margin: 0 0 16px; display: flex; align-items: center; gap: 10px; .h-icon { font-size: 28px; width: 28px; height: 28px; color: var(--cg-accent); } }
    .doc-h2 { font-size: 20px; font-weight: 700; color: var(--cg-text); margin: 0 0 12px; padding-bottom: 8px; border-bottom: 2px solid var(--cg-border); }
    .doc-h3 { font-size: 16px; font-weight: 700; color: var(--cg-text); margin: 0 0 10px; display: flex; align-items: center; gap: 8px; }
    .doc-lead { font-size: 15px; line-height: 1.7; color: var(--cg-text-muted); margin: 0 0 16px; }
    p { color: var(--cg-text-muted); line-height: 1.6; margin: 0 0 12px; font-size: 14px; }
    a { color: var(--cg-accent, #6366f1); text-decoration: none; &:hover { text-decoration: underline; } }
    .info-box { display: flex; gap: 10px; align-items: flex-start; background: color-mix(in srgb, #6366f1 8%, transparent); border: 1px solid color-mix(in srgb, #6366f1 30%, transparent); border-radius: 8px; padding: 12px 14px; margin: 12px 0; font-size: 13px; color: var(--cg-text);
      app-icon { color: #818cf8; flex-shrink: 0; margin-top: 1px; font-size: 18px; width: 18px; height: 18px; }
      &.warn { background: color-mix(in srgb, #f59e0b 8%, transparent); border-color: color-mix(in srgb, #f59e0b 30%, transparent); app-icon { color: #f59e0b; } } }
    .code-block { background: var(--cg-surface-1, #1e2530); border: 1px solid var(--cg-border, #3f4a5a); border-radius: 8px; padding: 14px 16px; font-family: 'JetBrains Mono', 'Fira Code', monospace; font-size: 13px; line-height: 1.6; color: #e2e8f0; white-space: pre; overflow-x: auto; margin: 10px 0 16px; }
    .doc-table { width: 100%; border-collapse: collapse; font-size: 13px; margin: 10px 0 16px;
      th { text-align: left; padding: 8px 12px; background: var(--cg-surface-1, #1e2530); border-bottom: 2px solid var(--cg-border); color: var(--cg-text); font-weight: 600; }
      td { padding: 8px 12px; border-bottom: 1px solid var(--cg-border); color: var(--cg-text-muted); vertical-align: top; code { background: var(--cg-surface-1, #1e2530); border-radius: 4px; padding: 1px 5px; font-family: monospace; color: #93c5fd; font-size: 12px; } }
      tr:last-child td { border-bottom: none; } }
    .step-badge { background: color-mix(in srgb, #6366f1 18%, transparent); border: 1px solid color-mix(in srgb, #6366f1 40%, transparent); color: #a5b4fc; padding: 2px 10px; border-radius: 6px; font-family: 'JetBrains Mono', monospace; font-size: 14px; }
    .badge { display: inline-block; font-size: 11px; font-weight: 700; padding: 2px 8px; border-radius: 10px;
      &.wayfarer    { background: #1e293b; color: #94a3b8; }
      &.explorer    { background: #1c2e1c; color: #86efac; }
      &.navigator   { background: #1e2a3a; color: #93c5fd; }
      &.cartographer{ background: #2d1515; color: #f87171; } }
    code { background: var(--cg-surface-1, #1e2530); border-radius: 4px; padding: 1px 5px; font-family: monospace; color: #93c5fd; font-size: 12px; }
    .doc-list { margin: 8px 0 12px; padding-left: 20px; li { color: var(--cg-text-muted); font-size: 14px; line-height: 1.8; } }
    .hierarchy { display: flex; flex-direction: column; gap: 4px; margin: 12px 0 16px; padding: 16px; background: var(--cg-surface-1, #1e2530); border-radius: 8px; border: 1px solid var(--cg-border); }
    .h-item { display: flex; align-items: center; gap: 8px; font-size: 14px; color: var(--cg-text); app-icon { color: var(--cg-accent); } span { color: var(--cg-text-muted); } }
    .h-arrow { color: var(--cg-text-muted); padding-left: 28px; font-size: 16px; }
    .steps-grid { display: flex; gap: 16px; margin: 12px 0 16px; flex-wrap: wrap; }
    .step-card { flex: 1; min-width: 180px; background: var(--cg-surface-1, #1e2530); border: 1px solid var(--cg-border); border-radius: 10px; padding: 16px; font-size: 13px; color: var(--cg-text-muted); p { margin: 2px 0; } strong { color: var(--cg-text); display: block; margin: 4px 0 6px; } }
    .db-icon { font-size: 28px; width: 28px; height: 28px; display: block; margin-bottom: 8px; &.mysql { color: #f97316; } &.postgres { color: #60a5fa; } }
    .doc-end-mark { display: flex; align-items: center; gap: 8px; margin-top: 32px; padding-top: 24px; border-top: 1px solid var(--cg-border); color: var(--cg-text-muted); font-size: 14px; app-icon { color: #4ade80; } }
    @media (max-width: 800px) { .docs-toc { display: none; } .docs-layout { padding: 16px 12px 60px; } }
  `],
})
export class DocsComponent implements OnInit {
  tocStructure = TOC_STRUCTURE;

  // Reactive computed — updates instantly when language signal changes
  c = computed(() => this.i18n.lang() === 'en' ? EN : PT);

  // Cron diagram labels (not translated — universal)
  cronMin   = 'minuto    ';
  cronHour  = 'hora      ';
  cronDay   = 'dia do mês';
  cronMonth = 'mês       ';
  cronWday  = 'dia da sem.';

  active = 'intro';

  constructor(
    private nav: NavContextService,
    private i18n: TranslationService,
  ) {}

  ngOnInit(): void {
    this.nav.set([{ label: 'Docs' }]);
  }

  scrollTo(id: string): void {
    this.active = id;
    document.getElementById(id)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  @HostListener('window:scroll')
  onScroll(): void {
    const ids = TOC_STRUCTURE.flatMap(s => [s.id, ...(s.children?.map(c => c.id) ?? [])]);
    for (const id of [...ids].reverse()) {
      const el = document.getElementById(id);
      if (el && el.getBoundingClientRect().top <= 120) {
        this.active = id;
        return;
      }
    }
  }
}
