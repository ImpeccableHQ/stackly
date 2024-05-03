export const config: Record<
  string,
  {
    orderFactory: {
      address: string;
      startBlock: number;
    };
  }
> = {
  gnosis: {
    orderFactory: {
      address: '0x45B91Da2834010751b17F1eadE0a5a7B64233add',
      startBlock: 26488660,
    },
  },
  mainnet: {
    orderFactory: {
      address: '0x8b1a70feccc6c2ae6017ddd8d0bebdd1bd6eb261',
      startBlock: 16816896,
    },
  },
};
