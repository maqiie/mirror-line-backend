# Frontend <-> backend contract test

Runs the dashboard's real `src/lib/api.js` against a live backend and checks every response
against the shapes in `src/lib/demo.js`, then exercises every action the UI performs.

```bash
# in mirrorline-web/
npm i -D vitest@2 jsdom
cp <this folder>/contract.test.js src/contract.test.js
cp <this folder>/vitest.config.js vitest.config.js
# backend running + seeded (bin/rails db:seed); then:
EMAIL=admin@example.com PASSWORD=change-me-please npx vitest run
# a different API origin:  API=http://localhost:3000 npx vitest run
```

It creates and deletes its own temporary follower account, and briefly toggles the global pause.
