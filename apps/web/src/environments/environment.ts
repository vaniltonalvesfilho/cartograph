// Default (development) environment. Production builds swap this for
// environment.prod.ts via angular.json `fileReplacements`.
export const environment = {
  production: false,
  apiBase: 'http://localhost:8080/api',
  graphqlHttp: 'http://localhost:8080/graphql',
  // Phoenix socket mount point — phoenix.js appends the /websocket transport.
  socketUrl: 'ws://localhost:8080/socket',
};
