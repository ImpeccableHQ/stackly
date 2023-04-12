import dayjs, { Dayjs, isDayjs } from 'dayjs';
import { BigNumber, constants } from 'ethers';
import { useEffect, useState } from 'react';
import {
  USDC,
  ChainId,
  Amount,
  WETH,
  DCAFrequencyInterval,
  getOrderFactory,
  getOrderFactoryAddress,
  createDCAOrderWithNonce,
  getorderAddressFromTransactionReceipt,
  getERC20Contract,
  Currency,
} from 'dca-sdk';
import { FormGroup } from '../form/FormGroup';
import { FlexContainer, FormButtonGroup, InnerContainer } from './styled';
import dayjsUTCPlugin from 'dayjs/plugin/utc';
import { useAccount, useNetwork, useSigner, useSwitchNetwork } from 'wagmi';
import { CardExtraShadow as Card, CardInnerWrapper } from '../Card';
import { Container } from '../Container';
import { Modal, useModal } from '../../modal';
import styled from 'styled-components';
import { VaultCreateAndDepositStepsModalProps, CreateVaultAndDepositStep } from '../Modal/CreateVaultSteps';
import { FrequencyIntervalSelect, getFrequencyIntervalInHours } from './FrequencyIntervalSelect';
import { DateTimeInput } from '../form/DateTime';
import { CurrencyAmountInput } from '../CurrencyAmountInput';
import { CurrencyInput } from '../CurrencyAmountInput/CurrencyInput';
import { Button } from '../../ui/components/Button/Button';
import { useCurrencyBalance } from '../../tokens/hooks';

dayjs.extend(dayjsUTCPlugin);

function WalletConnectButton() {
  const account = useAccount();
  const { openModal } = useModal();
  const { chain } = useNetwork();
  const { switchNetworkAsync } = useSwitchNetwork();
  const isNetworkSupported = chain && !chain.unsupported;

  if (account.isConnected && !isNetworkSupported) {
    return (
      <Button type="button" onClick={() => switchNetworkAsync?.(ChainId.GNOSIS)}>
        Switch Network
      </Button>
    );
  }

  return (
    <Button type="button" onClick={() => openModal(Modal.Wallet)} title="Connect Wallet">
      Connect Wallet
    </Button>
  );
}

function getInitialSellTokenAmountValue(chain?: ReturnType<typeof useNetwork>['chain']) {
  return chain && chain.id && !chain.unsupported
    ? new Amount(USDC[chain.id as ChainId], '0')
    : new Amount(USDC[ChainId.ETHEREUM], '0');
}

function getInitialBuyTokenValue(chain?: ReturnType<typeof useNetwork>['chain']) {
  return chain && chain.id && !chain.unsupported ? WETH[chain.id as ChainId] : WETH[ChainId.ETHEREUM];
}

export function CreateDCAVaultContainer() {
  const account = useAccount();
  const { chain, chains } = useNetwork();
  const { openModal, setModalData } = useModal<VaultCreateAndDepositStepsModalProps>();
  const { data: signer } = useSigner();
  const [validationError, setValidationError] = useState<Error | null>(null);
  const [startAt, setStartAt] = useState<Dayjs>(dayjs().add(10, 'm'));
  const [endAt, setEndAt] = useState<Dayjs>(dayjs().add(7, 'd')); // 7 days from now
  const [hourInterval, setHourInterval] = useState<number>(1);
  const [frequencyInterval, setFrequencyInterval] = useState<DCAFrequencyInterval>(DCAFrequencyInterval.HOUR);
  const [sellTokenAmount, setSellTokenAmount] = useState<Amount<Currency>>(getInitialSellTokenAmountValue(chain));
  const { balance: userSellTokenBalance } = useCurrencyBalance(account.address, sellTokenAmount.currency);
  const [buyToken, setBuyToken] = useState<Currency>(getInitialBuyTokenValue(chain));
  const [createVaultError, setCreateVaultError] = useState<Error | null>(null);
  const [receiver] = useState<string | null>(null);
  const [allowance, setAllowance] = useState<BigNumber | null>(null);

  // Update initial values when chain changes
  useEffect(() => {
    setSellTokenAmount(getInitialSellTokenAmountValue(chain));
    setBuyToken(getInitialBuyTokenValue(chain));
  }, [signer, chain]);

  // Update allowance when account or sell token changes
  useEffect(() => {
    if (!signer || !account.address || !sellTokenAmount.currency.address) {
      return;
    }
    let factoryAddress;
    try {
      factoryAddress = getOrderFactoryAddress(chain?.id as ChainId);
      getERC20Contract(sellTokenAmount.currency.address, signer)
        .allowance(account.address, factoryAddress)
        .then(setAllowance);
    } catch (e) {
      console.error(e);
    }
  }, [signer, account.address, sellTokenAmount.currency.address, chain]);

  // Validate the user has enough balance
  useEffect(() => {
    if (!signer || !account.address || !sellTokenAmount.currency.address || !userSellTokenBalance) {
      return;
    }
    if (userSellTokenBalance?.lessThan(sellTokenAmount)) {
      setValidationError(new Error('Insufficient balance'));
    } else {
      setValidationError(null);
    }
  }, [userSellTokenBalance, signer, account.address, sellTokenAmount]);

  const isNetworkSupported = !!chains.find((c) => c.id === chain?.id);

  const onCreateOrderHandler = async () => {
    setCreateVaultError(null);

    // Start date must be in the future
    if (isDayjs(startAt) && startAt.isBefore(dayjs())) {
      return setCreateVaultError(new Error('Start date must be in the future'));
    }
    // End date must be after start date
    if (endAt.isBefore(startAt)) {
      return setCreateVaultError(new Error('End date must be after start date'));
    }

    if (!signer) {
      return setCreateVaultError(new Error('No signer found'));
    }

    if (sellTokenAmount.eq('0')) {
      return setCreateVaultError(new Error(`${sellTokenAmount.currency.symbol} amount must be greater than zero`));
    }

    const chainId = chain?.id as ChainId;
    let orderProxy: undefined | string;
    // Open the modal with initial required data
    openModal(Modal.VaultCreateAndDepositSteps, {
      chainId,
      stepsCompleted: [],
      tokenSymbol: sellTokenAmount.currency.symbol as string,
      tokenDepositAmount: parseFloat(sellTokenAmount.toFixed(3)),
    });

    const sellTokenContract = getERC20Contract(sellTokenAmount.currency.address, signer);

    // Skip to next step if allowance is sufficient
    if (allowance && allowance.gt(sellTokenAmount.toRawAmount())) {
      setModalData((prev) => ({
        ...prev,
        stepsCompleted: [CreateVaultAndDepositStep.APPROVE_FACTORY],
        approveFactoryReceipt: {} as any,
      }));
    } else {
      // Approve factory to spend sell token
      const approveFactoryTransaction = await sellTokenContract.approve(
        getOrderFactoryAddress(chainId),
        constants.MaxUint256
      );

      setModalData((prev) => ({
        ...prev,
        approveFactoryTransaction,
      }));

      const approveFactoryReceipt = await approveFactoryTransaction.wait();

      setModalData((prev) => ({
        ...prev,
        stepsCompleted: [CreateVaultAndDepositStep.APPROVE_FACTORY],
        approveFactoryReceipt,
      }));
    }
    // Create a new vault if one doesn't exist
    const orderFactory = getOrderFactory(getOrderFactoryAddress(chainId), signer);

    const initParams: Parameters<typeof createDCAOrderWithNonce>['1'] = {
      nonce: dayjs().unix(),
      // dca order params
      owner: account.address as string,
      receiver: receiver ?? (account.address as string), // TODO: add receiver
      sellToken: sellTokenAmount.currency.address,
      buyToken: buyToken.address,
      principal: sellTokenAmount.toRawAmount().toString(),
      // If startAt is 'now', set it to the current time plus 10 minutes into the future
      startTime:
        startAt.utc().unix() < dayjs().add(10, 'm').utc().unix()
          ? dayjs().add(10, 'm').utc().unix()
          : startAt.utc().unix(),
      endTime: endAt.utc().unix(),
      interval: hourInterval,
    };

    console.log('initParams', initParams);

    const createOrderTransaction = await createDCAOrderWithNonce(orderFactory, initParams);

    setModalData((prev) => ({
      ...prev,
      createOrderTransaction,
    }));

    const createOrderReceipt = await createOrderTransaction.wait();

    if (!createOrderReceipt.status) {
      setCreateVaultError(new Error('Could not create vault'));
      return;
    }

    orderProxy = getorderAddressFromTransactionReceipt(createOrderReceipt);

    if (!orderProxy) {
      setCreateVaultError(new Error('Could not create vault'));
      return;
    }

    setModalData((prev) => ({
      ...prev,
      stepsCompleted: [...prev.stepsCompleted, CreateVaultAndDepositStep.CREATE_ORDER],
      createOrderReceipt,
      orderProxy,
      isOrderCreated: true,
    }));
  };

  /*
   * @TODO: uncomment if there's use for this
  // Calculate the number of buy orders
  const buyOrders = Math.ceil(endAt.diff(startAt, 'hours') / hourInterval);
  const buyAmountPerOrder = sellTokenAmount.div(buyOrders === 0 ? 1 : buyOrders);
  */

  return (
    <Container>
      <FlexContainer>
        <InnerContainer>
          <Card>
            <CardInnerWrapper>
              <form>
                <FormGroup>
                  <label>From</label>
                  <CurrencyAmountInput
                    disabled={!isNetworkSupported}
                    value={sellTokenAmount}
                    showNativeCurrency={false}
                    userAddress={account.address}
                    onChange={(nextSellAmount) => {
                      // If the user select a token that is the same as the buy token, we swap the buy token
                      if (nextSellAmount.currency.equals(buyToken)) {
                        const nextBuyToken = sellTokenAmount.currency;
                        setBuyToken(nextBuyToken);
                      }
                      setSellTokenAmount(nextSellAmount);
                      setCreateVaultError(null);
                    }}
                  />
                </FormGroup>
                <JoinedFormGroup>
                  <FormGroup id="buy-currency">
                    <label>Stack</label>
                    <CurrencyInput
                      disabled={!isNetworkSupported}
                      showNativeCurrency={false}
                      value={buyToken}
                      onChange={(nextBuyToken) => {
                        // Prevent selecting the same token for buy and sell
                        if (nextBuyToken.equals(sellTokenAmount.currency)) {
                          return;
                        }
                        setBuyToken(nextBuyToken);
                      }}
                    />
                  </FormGroup>
                  <FormGroup id="buy-frequency">
                    <label>Every</label>
                    <FrequencyIntervalSelect
                      disabled={!isNetworkSupported}
                      value={frequencyInterval}
                      onChange={(nextFrequencyInterval) => {
                        const nextHourInterval = getFrequencyIntervalInHours(nextFrequencyInterval);
                        setFrequencyInterval(nextFrequencyInterval);
                        setHourInterval(nextHourInterval);
                      }}
                    />
                  </FormGroup>
                </JoinedFormGroup>
                <FormGroup>
                  <label>Starting</label>
                  <DateTimeInput onChange={setStartAt} value={startAt} disabled={!isNetworkSupported} />
                </FormGroup>
                <FormGroup>
                  <label>Until</label>
                  <DateTimeInput onChange={setEndAt} value={endAt} disabled={!isNetworkSupported} />
                </FormGroup>
                <FormButtonGroup>
                  {account.isConnected && isNetworkSupported ? (
                    <Button
                      type="button"
                      onClick={onCreateOrderHandler}
                      title="Create Order"
                      disabled={validationError !== null}
                    >
                      {validationError !== null ? validationError.message : <>Stack</>}
                    </Button>
                  ) : (
                    <WalletConnectButton />
                  )}
                </FormButtonGroup>
              </form>
              {/* buyAmountPerOrder.greaterThan(0) && (
                <OrderInfo>
                  <p>
                    Buying {buyAmountPerOrder.toFixed(2)} {sellTokenAmount.currency.symbol} worth of {buyToken.symbol}{' '}
                    every {frequencyInterval} for {buyOrders} times
                  </p>
                </OrderInfo>
              ) */}
              {createVaultError && (
                <div>
                  <p>{createVaultError.message}</p>
                </div>
              )}
            </CardInnerWrapper>
          </Card>
        </InnerContainer>
      </FlexContainer>
    </Container>
  );
}

export const OrderInfo = styled.div`
  font-size: 18px;
  font-weight: bold;
`;

const JoinedFormGroup = styled.div`
  display: flex;
  flex-direction: column;
  gap: 8px;
  & #buy-currency button {
    height: 100%;
  }
  & #buy-frequency {
    flex: 1;
  }
  @media (min-width: 320px) {
    flex-direction: row;
  }
`;
