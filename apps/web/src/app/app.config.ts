import { APP_INITIALIZER, ApplicationConfig } from '@angular/core';
import { provideRouter } from '@angular/router';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { provideAnimationsAsync } from '@angular/platform-browser/animations/async';
import { provideApollo } from 'apollo-angular';
import { HttpLink } from 'apollo-angular/http';
import { inject } from '@angular/core';
import { InMemoryCache } from '@apollo/client/core';
import { routes } from './app.routes';
import { authInterceptor } from './services/auth.interceptor';
import { AuthService } from './services/auth.service';
import { environment } from '../environments/environment';

function initAuth(auth: AuthService) {
  return () => auth.restoreSession();
}

export const appConfig: ApplicationConfig = {
  providers: [
    provideRouter(routes),
    provideHttpClient(withInterceptors([authInterceptor])),
    provideAnimationsAsync(),
    {
      provide: APP_INITIALIZER,
      useFactory: initAuth,
      deps: [AuthService],
      multi: true,
    },
    // Apollo handles queries/mutations over HTTP only; subscriptions go through
    // the Phoenix channel transport (AbsintheSocketService) — the backend's
    // Absinthe.Phoenix socket does not speak the graphql-ws protocol.
    provideApollo(() => {
      const httpLink = inject(HttpLink);
      return {
        link: httpLink.create({ uri: environment.graphqlHttp }),
        cache: new InMemoryCache(),
      };
    }),
  ],
};
