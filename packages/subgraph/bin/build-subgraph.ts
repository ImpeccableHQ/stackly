import { writeFile } from 'fs/promises';
import { stringify as yamlStringify } from 'yaml';

import { config } from './config';

async function main() {
  // get network from command line
  const network = process.argv[2] as string | undefined;
  // validate network
  if (!network || !['mainnet', 'gnosis'].includes(network)) {
    throw new Error('Invalid network. Must be one of: mainnet, gnosis');
  }

  const subgraph = {
    specVersion: '0.0.4',
    features: ['nonFatalErrors'],
    schema: {
      file: './schema.graphql',
    },
    dataSources: [
      {
        name: 'OrderFactory',
        kind: 'ethereum/contract',
        network,
        source: {
          address: config[network].orderFactory.address,
          startBlock: config[network].orderFactory.startBlock,
          abi: 'OrderFactory',
        },
        mapping: {
          kind: 'ethereum/events',
          apiVersion: '0.0.6',
          language: 'wasm/assemblyscript',
          file: './src/mappings/factory.ts',
          entities: ['OrderFactory'],
          abis: [
            {
              name: 'OrderFactory',
              file: './abis/OrderFactory.json',
            },
          ],
          eventHandlers: [
            {
              event: 'OrderCreated(indexed address)',
              handler: 'handleDCAOrderCreated',
            },
          ],
        },
      },
    ],
    templates: [
      {
        name: 'DCAOrder',
        kind: 'ethereum/contract',
        network,
        source: {
          abi: 'DCAOrder',
        },
        mapping: {
          kind: 'ethereum/events',
          apiVersion: '0.0.6',
          language: 'wasm/assemblyscript',
          file: './src/mappings/order.ts',
          entities: ['OrderFactory', 'Order', 'Token'],
          abis: [
            {
              name: 'OrderFactory',
              file: './abis/OrderFactory.json',
            },
            {
              name: 'DCAOrder',
              file: './abis/DCAOrder.json',
            },
            {
              name: 'ERC20',
              file: './abis/ERC20.json',
            },
          ],
          eventHandlers: [
            {
              event: 'Initialized(indexed address)',
              handler: 'handleDCAOrderInitialized',
            },
            {
              event: 'Cancelled(indexed address)',
              handler: 'handleDCAOrderCancelled',
            },
          ],
        },
      },
    ],
  };

  await writeFile(`./subgraph.yaml`, yamlStringify(subgraph));
}

main();
