// packages/backend/src/modules/vela.ts
//
// NOTE: This part is NOT expressible as pure config. It has to be built
// into your Backstage app image before the Helm chart deploys it.
// This is the "missing part" that trips people up: app-config.yaml alone
// does not register the entity provider, this code does.
//
// This targets the NEW backend system (backend.add(...) calls in a
// single packages/backend/src/index.ts), which is what
// `npx @backstage/create-app@latest` scaffolds by default as of this
// writing. @oamdev/plugin-kubevela-backend only ships the older
// "plugin-file" pattern's VelaProvider class, no ready-made module for
// the new backend system, so this file wraps it manually. Wire it in:
//
//   backend.add(import('./modules/vela'));
//
// alongside your other backend.add(...) calls, before backend.start().
//
// If your app still uses the OLD backend system (a
// packages/backend/src/plugins/catalog.ts file, CatalogBuilder.create),
// see the bottom of this file for that variant instead.

import {
  coreServices,
  createBackendModule,
} from '@backstage/backend-plugin-api';
import { catalogProcessingExtensionPoint } from '@backstage/plugin-catalog-node';
import { VelaProvider } from '@oamdev/plugin-kubevela-backend';
import type { UrlReader } from '@backstage/backend-common';

export default createBackendModule({
  pluginId: 'catalog',
  moduleId: 'vela-provider',
  register(reg) {
    reg.registerInit({
      deps: {
        catalog: catalogProcessingExtensionPoint,
        config: coreServices.rootConfig,
        reader: coreServices.urlReader,
        scheduler: coreServices.scheduler,
        logger: coreServices.logger,
      },
      async init({ catalog, config, reader, scheduler, logger }) {
        // VelaProvider was written for the older UrlReader interface,
        // which had a simple `.read(url): Promise<Buffer>` method. The
        // new backend system's urlReader service only exposes
        // readUrl/readTree/search, so we shim a `.read()` on top of
        // readUrl() to bridge the two.
        const readerShim = {
          ...reader,
          read: async (url: string) => {
            const response = await reader.readUrl(url);
            return response.buffer();
          },
        };
        const vela = new VelaProvider('production', readerShim as any, config);
        catalog.addEntityProvider(vela);

        // NOTE: VelaProvider reads its config from a flat `vela:` block
        // at the root of app-config.yaml, not from
        // catalog.providers.vela.<id>; that nesting belongs to a
        // different, newer integration path this package does not
        // ship. Keep these keys in sync with backstage/helm-values.yaml.tpl.
        const frequency = config.getOptionalNumber('vela.frequency') ?? 30;
        const timeout = config.getOptionalNumber('vela.timeout') ?? 60;

        await scheduler.scheduleTask({
          id: 'run_vela_refresh',
          fn: async () => {
            try {
              await vela.run();
            } catch (err) {
              const text =
                err instanceof Error ? (err.stack ?? err.message) : String(err);
              logger.error(`vela.run() failed: ${text}`);
            }
          },
          frequency: { seconds: frequency },
          timeout: { seconds: timeout },
        });

        logger.info('KubeVela entity provider registered and scheduled');
      },
    });
  },
});

/*
=== OLD BACKEND SYSTEM VARIANT ===
Only use this if your app has packages/backend/src/plugins/catalog.ts
and packages/backend/src/index.ts does NOT use backend.add(...). Put
this in packages/backend/src/plugins/catalog.ts instead of the above.

import { CatalogBuilder } from '@backstage/plugin-catalog-backend';
import { ScaffolderEntitiesProcessor } from '@backstage/plugin-catalog-backend-module-scaffolder-entity-model';
import { VelaProvider } from '@oamdev/plugin-kubevela-backend';
import { Router } from 'express';
import { PluginEnvironment } from '../types';

export default async function createPlugin(
  env: PluginEnvironment,
): Promise<Router> {
  const builder = await CatalogBuilder.create(env);

  const vela = new VelaProvider('production', env.reader, env.config);
  builder.addEntityProvider(vela);
  builder.addProcessor(new ScaffolderEntitiesProcessor());

  const { processingEngine, router } = await builder.build();
  await processingEngine.start();

  const frequency = env.config.getOptionalNumber('vela.frequency') ?? 30;
  const timeout = env.config.getOptionalNumber('vela.timeout') ?? 60;

  await env.scheduler.scheduleTask({
    id: 'run_vela_refresh',
    fn: async () => {
      await vela.run();
    },
    frequency: { seconds: frequency },
    timeout: { seconds: timeout },
  });

  return router;
}
*/
