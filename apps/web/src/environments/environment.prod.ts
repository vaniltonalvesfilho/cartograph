// Production environment: same-origin relative URLs, assuming the API and the
// SPA are served behind one reverse proxy. Adjust per deployment topology.
const wsProto = location.protocol === 'https:' ? 'wss' : 'ws';

export const environment = {
  production: true,
  apiBase: '/api',
  graphqlHttp: '/graphql',
  // Phoenix socket mount point — phoenix.js appends the /websocket transport.
  socketUrl: `${wsProto}://${location.host}/socket`,
};
