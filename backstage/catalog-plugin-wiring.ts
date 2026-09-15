// packages/backend/src/plugins/catalog.ts
//
// NOTE: This part is NOT expressible as pure config. It has to be built
// into your Backstage app image before the Helm chart deploys it.
// This is the "missing part" that trips people up: app-config.yaml alone
// does not register the entity provider, this code does.

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

  // NOTE: VelaProvider (older-backend pattern) reads its config from a
  // flat `vela:` block at the root of app-config.yaml, not from
  // catalog.providers.vela.<id>; that nesting belongs to the newer
  // velaProviderModule integration and is not what's wired up here.
  // Keep these keys in sync with backstage/helm-values.yaml.tpl.
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
