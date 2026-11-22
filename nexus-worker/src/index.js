import { handle } from './app.js';

export { QuotaDO } from './quota_do.js';

export default {
  async fetch(request, env) {
    return handle(request, env);
  },
};
