import {
  IERC20Metadata,
  IERC20Metadata__factory,
  IOrigamiInvestment,
  IOrigamiInvestment__factory,
} from '@/typechain';
import {
  chainIdKey,
  contractAddressKey,
  newToken,
  tokenKey,
  tokenOrNativeAmountDecimals,
} from '@/utils/api-utils';
import {
  createMemoizedAsyncValue,
  createMemoizedAsyncMap,
  MemoizedAsyncMap,
} from '@/utils/memoized';
import { DecimalBigNumber } from '@/utils/decimal-big-number';
import { VMap } from '@/utils/vmap';
import {
  BigNumber,
  ContractReceipt,
  ContractTransaction,
  ethers,
  providers,
  Signer,
} from 'ethers';
import {
  ExitQuoteReq,
  ExitQuoteResp,
  ExitReq,
  ExitResp,
  HistoricMetricReq,
  InvestQuoteReq,
  InvestQuoteResp,
  InvestReq,
  InvestResp,
  HistoricTokenUsdPriceReq,
  MetricsResp,
  ProviderApi,
  SignerApi,
} from './api';
import {
  Chain,
  ChainId,
  ContractAddress,
  HistoricPeriod,
  HistoryPoint,
  Investment,
  InvestmentConfig,
  PriceContractConfig,
  Token,
  TokenConfig,
  TokenOrNative,
} from './types';
import {
  dateFromTimestamp,
  percentFromSubgraph,
  queryInvestmentVaultDailySnapshots as queryInvestmentVaultDailySnapshots,
  queryInvestmentVaultHourlySnapshots,
  queryInvestmentVaultMetrics,
  queryPricedTokenDailySnapshots,
  queryPricedTokenHourlySnapshots,
  subgraphQuery,
} from './subgraph';
import { ITokenPrices__factory } from '@/typechain/factories/ITokenPrices__factory';
import { ITokenPrices } from '@/typechain/ITokenPrices';
import { first, matchEvents } from './utils';

export interface ApiConfig {
  chains: Chain[];
  tokens: ExtendedTokenConfig[];
  investments: InvestmentConfig[];
  priceContracts: PriceContractConfig[];
}

export interface ExtendedTokenConfig extends TokenConfig {
  iconName: string;
}

export function createProviderApi(config: ApiConfig): ProviderApi {
  return new ProviderApiImpl(config);
}

export function createSignerApi(
  config: ApiConfig,
  signerAddress: string,
  chainId: ChainId,
  signer: Signer
): SignerApi {
  return new SignerApiImpl(config, signerAddress, chainId, signer);
}

class ProviderApiImpl implements ProviderApi {
  chains: VMap<ChainId, Chain>;
  investments: InvestmentConfig[];
  providers: VMap<ChainId, providers.BaseProvider>;
  tokens: MemoizedAsyncMap<TokenConfig, Token>;
  tokenUsdPrices: MemoizedAsyncMap<Token, DecimalBigNumber>;
  nativeUsdPrices: MemoizedAsyncMap<ChainId, DecimalBigNumber>;
  loadedInvestments: MemoizedAsyncMap<InvestmentConfig, Investment>;
  subgraphUrls: VMap<ChainId, string>;

  constructor(readonly config: ApiConfig) {
    console.log('api: new ProviderApiImpl');
    this.investments = config.investments;
    this.chains = new VMap((c) => c.toString());
    for (const c of config.chains) {
      this.chains.put(c.id, c);
    }
    this.providers = new VMap<ChainId, providers.BaseProvider>((cid) =>
      cid.toString()
    );
    this.tokens = createMemoizedAsyncMap(
      (tc) => tc.address + '/' + tc.chainId,
      (tc) => this.loadToken(tc)
    );
    this.loadedInvestments = createMemoizedAsyncMap(
      (ic) => contractAddressKey(ic.contractAddress),
      (ic) => this.loadInvestment(ic)
    );
    this.subgraphUrls = new VMap<ChainId, string>(chainIdKey);
    for (const c of config.chains) {
      this.subgraphUrls.put(c.id, c.subgraphUrl);
    }
    this.tokenUsdPrices = createMemoizedAsyncMap(tokenKey, (t) =>
      this.loadTokenUsdPrice(t)
    );
    this.nativeUsdPrices = createMemoizedAsyncMap(chainIdKey, (c) =>
      this.loadNativeUsdPrice(c)
    );

    setInterval(() => this.every60Secs(), 60000);
  }

  private getProvider(chainId: ChainId): providers.BaseProvider {
    let provider = this.providers.get(chainId);
    if (provider === undefined) {
      const chain = this.chains.get(chainId);
      if (chain === undefined) {
        throw new Error('No chain configured for chain id ' + chainId);
      }
      console.log(
        'api: new provider for chain ' + chainId + ' via ' + chain.rpcUrl
      );
      provider = ethers.getDefaultProvider(chain.rpcUrl);
      this.providers.put(chainId, provider);
    }
    return provider;
  }

  private getChain(chainId: ChainId): Chain {
    const chain = this.chains.get(chainId);
    if (!chain) {
      throw new Error(`chain ${chainId} not configured`);
    }
    return chain;
  }

  getToken(config: TokenConfig): Promise<Token> {
    return this.tokens.get(config);
  }

  private async loadToken(config: TokenConfig): Promise<Token> {
    const econfig = this.config.tokens.find(
      (t) => t.address == config.address && t.chainId == config.chainId
    );

    const symbol = econfig?.symbol;
    const decimals = econfig?.decimals;
    const iconName = econfig?.iconName || 'error';

    if (symbol && decimals) {
      return newToken(symbol, iconName, decimals, config);
    }
    return logged(this.loadTokenFromChain(config, iconName), {
      label: 'loadTokenFromChain',
      req: [config],
      resp: (v) => v,
    });
  }

  private async loadTokenFromChain(
    config: TokenConfig,
    iconName: string
  ): Promise<Token> {
    const provider = this.getProvider(config.chainId);
    const tc = IERC20Metadata__factory.connect(config.address, provider);
    const [symbol, decimals] = await Promise.all([tc.symbol(), tc.decimals()]);
    const token = newToken(symbol, iconName, decimals, config);

    // Uncomment to log loaded tokens in a format suitable for pasting into config.
    // console.log(`const ${token.symbol.toUpperCase()}_TOKEN: ExtendedTokenConfig = ${JSON.stringify({
    //   address: token.config.address,
    //   chainId: token.config.chainId,
    //   iconName: 'error',
    //   symbol:  token.symbol,
    //   decimals: token.decimals,
    // }, null, 2)}`);

    return token;
  }

  async getInvestment(config: InvestmentConfig): Promise<Investment> {
    return this.loadedInvestments.get(config);
  }

  private async loadInvestment(ic: InvestmentConfig): Promise<Investment> {
    return logged(this.loadInvestment_(ic), {
      label: 'loadInvestment',
      req: [ic],
      resp: (v) => v,
    });
  }

  private async loadInvestment_(ic: InvestmentConfig): Promise<Investment> {
    const chainId = ic.contractAddress.chainId;
    const chain = this.getChain(chainId);
    const provider = this.getProvider(chainId);
    const contract = IOrigamiInvestment__factory.connect(
      ic.contractAddress.address,
      provider
    );

    // The investment contract itself is now the receipt token.
    const receiptTokenAddr = contract.address;
    const receiptToken: Token = await this.getToken({
      address: receiptTokenAddr,
      chainId,
    });

    const acceptedInvestTokens = createMemoizedAsyncValue(async () => {
      return this.getAcceptedTokens(
        chain,
        await contract.acceptedInvestTokens()
      );
    }).get;

    const acceptedExitTokens = createMemoizedAsyncValue(async () => {
      return this.getAcceptedTokens(chain, await contract.acceptedExitTokens());
    }).get;

    const getMetrics_ = async (): Promise<MetricsResp> => {
      const url = this.getSubgraphUrl(chainId);
      const query = queryInvestmentVaultMetrics(ic.contractAddress);
      const result = await subgraphQuery(url, query);
      if (!result.investmentVault) {
        throw new Error('No metrics returned');
      }
      return {
        tvl: parseFloat(result.investmentVault.tvl),
        apy: parseFloat(result.investmentVault.apy) / 100,
      };
    };

    const getMetrics = async (): Promise<MetricsResp> => {
      return logged(getMetrics_(), {
        label: 'getMetrics',
        req: [ic],
        resp: (v) => v,
      });
    };

    const getHistoricMetric = async (
      req: HistoricMetricReq
    ): Promise<HistoryPoint[]> => {
      return this.getHistoricMetric(ic.contractAddress, req);
    };

    const investment = {
      ...ic,
      chain,
      receiptToken,
      acceptedInvestTokens,
      acceptedExitTokens,
      getMetrics,
      getHistoricMetric,
    };
    return investment;
  }

  private async getAcceptedTokens(
    chain: Chain,
    tokenaddrs: string[]
  ): Promise<TokenOrNative[]> {
    return Promise.all(tokenaddrs.map((a) => this.getAcceptedToken(chain, a)));
  }

  private async getAcceptedToken(
    chain: Chain,
    address: string
  ): Promise<TokenOrNative> {
    if (address === ethers.constants.AddressZero) {
      return { kind: 'native', chain };
    }
    const token = await this.getToken({ address, chainId: chain.id });
    return { kind: 'token', token };
  }

  async getNativeBalance(
    chain: ChainId,
    address: string
  ): Promise<DecimalBigNumber> {
    return logged(this.getNativeBalance_(chain, address), {
      label: 'getNativeBalance',
      req: [chain, address],
      resp: (v) => v,
    });
  }

  private async getNativeBalance_(
    chain: ChainId,
    address: string
  ): Promise<DecimalBigNumber> {
    const provider = this.getProvider(chain);
    const balance = await provider.getBalance(address);
    const decimals = this.chains.get(chain)?.nativeCurrency.decimals || 18;
    return DecimalBigNumber.fromBN(balance, decimals);
  }

  async getTokenBalance(
    token: Token,
    address: string
  ): Promise<DecimalBigNumber> {
    return logged(this.getTokenBalance_(token, address), {
      label: 'getTokenBalance',
      req: [token, address],
      resp: (v) => v,
    });
  }

  private async getTokenBalance_(
    token: Token,
    address: string
  ): Promise<DecimalBigNumber> {
    const provider = this.getProvider(token.config.chainId);
    const tc = IERC20Metadata__factory.connect(token.config.address, provider);
    const balance = await tc.balanceOf(address);
    return DecimalBigNumber.fromBN(balance, token.decimals);
  }

  async getTokenUsdPrice(token: Token): Promise<DecimalBigNumber> {
    return this.tokenUsdPrices.get(token);
  }

  async getNativeUsdPrice(chainId: ChainId): Promise<DecimalBigNumber> {
    return this.nativeUsdPrices.get(chainId);
  }

  private async loadTokenUsdPrice(token: Token): Promise<DecimalBigNumber> {
    return logged(this.loadTokenUsdPrice_(token), {
      label: 'loadTokenUsdPrice',
      req: [token],
      resp: (v) => v,
    });
  }

  private async loadTokenUsdPrice_(token: Token): Promise<DecimalBigNumber> {
    const pc = await this.getPriceContract(token.config.chainId);
    const price = await pc.tokenPrice(token.config.address);
    const precision = await this.getPriceDecimals(pc);
    return DecimalBigNumber.fromBN(price, precision);
  }

  private async loadNativeUsdPrice(
    chainId: ChainId
  ): Promise<DecimalBigNumber> {
    return logged(this.loadNativeUsdPrice_(chainId), {
      label: 'loadNativeUsdPrice',
      req: [chainId],
      resp: (v) => v,
    });
  }

  private async loadNativeUsdPrice_(
    chainId: ChainId
  ): Promise<DecimalBigNumber> {
    const pc = await this.getPriceContract(chainId);
    const price = await pc.tokenPrice(ethers.constants.AddressZero);
    const precision = await this.getPriceDecimals(pc);
    return DecimalBigNumber.fromBN(price, precision);
  }

  private async getPriceContract(chainId: ChainId): Promise<ITokenPrices> {
    const provider = this.getProvider(chainId);
    for (const pc of this.config.priceContracts) {
      if (pc.chainId == chainId) {
        return ITokenPrices__factory.connect(pc.address, provider);
      }
    }
    throw new Error('No price contracts configured for chain ' + chainId);
  }

  async getPriceDecimals(contract: ITokenPrices): Promise<number> {
    return await contract.decimals();
  }

  getSubgraphUrl(chainId: ChainId): string {
    const url = this.subgraphUrls.get(chainId);
    if (!url) {
      throw new Error('No subgraph for chainid ' + chainId);
    }
    return url;
  }

  async getHistoricTokenUsdPrice(
    req: HistoricTokenUsdPriceReq
  ): Promise<HistoryPoint[]> {
    const url = this.getSubgraphUrl(req.token.config.chainId);
    const { first, qtype } = this.historicTimeParams(req.period);

    if (qtype === 'hourly') {
      const query = queryPricedTokenHourlySnapshots(req.token, first);
      const result = await subgraphQuery(url, query);
      return result.pricedTokenHourlySnapshots.map((p) => {
        return {
          t: dateFromTimestamp(p.timeframe),
          v: parseFloat(p.price),
        };
      });
    } else {
      const query = queryPricedTokenDailySnapshots(req.token, first);
      const result = await subgraphQuery(url, query);
      return result.pricedTokenDailySnapshots.map((p) => {
        return {
          t: dateFromTimestamp(p.timeframe),
          v: parseFloat(p.price),
        };
      });
    }
  }

  async getHistoricMetric(
    investmentAddress: ContractAddress,
    req: HistoricMetricReq
  ): Promise<HistoryPoint[]> {
    const url = this.getSubgraphUrl(investmentAddress.chainId);

    const { first, qtype } = this.historicTimeParams(req.period);

    if (qtype === 'hourly') {
      const query = queryInvestmentVaultHourlySnapshots(
        investmentAddress,
        first
      );
      const result = await subgraphQuery(url, query);
      return result.investmentVaultHourlySnapshots.map((p) => {
        return {
          t: dateFromTimestamp(p.timeframe),
          v:
            req.metric == 'apy'
              ? percentFromSubgraph(p.apy)
              : parseFloat(p.tvl),
        };
      });
    } else {
      const query = queryInvestmentVaultDailySnapshots(
        investmentAddress,
        first
      );
      const result = await subgraphQuery(url, query);
      return result.investmentVaultDailySnapshots.map((p) => {
        return {
          t: dateFromTimestamp(p.timeframe),
          v:
            req.metric == 'apy'
              ? percentFromSubgraph(p.apy)
              : parseFloat(p.tvl),
        };
      });
    }
  }

  historicTimeParams(period: HistoricPeriod): {
    first: number;
    qtype: 'hourly' | 'daily';
  } {
    let first = 1000;
    switch (period) {
      case 'day':
        first = 24;
        break;
      case 'week':
        first = 24 * 7;
        break;
      case 'month':
        first = 30;
        break;
      case 'all':
        first = 1000;
        break;
    }

    if (period === 'day' || period == 'week') {
      return { first, qtype: 'hourly' };
    } else {
      return { first, qtype: 'daily' };
    }
  }

  async investQuote(req: InvestQuoteReq): Promise<InvestQuoteResp> {
    return logged(this.investQuote_(req), {
      label: 'investQuote',
      req: [req],
      resp: (v) => v,
    });
  }

  private async investQuote_(req: InvestQuoteReq): Promise<InvestQuoteResp> {
    const provider = this.getProvider(req.investment.chain.id);
    const contract = IOrigamiInvestment__factory.connect(
      req.investment.contractAddress.address,
      provider
    );
    const amountDecimals = tokenOrNativeAmountDecimals(req.from);
    const amount = req.amount.toBN(amountDecimals);

    const fromTokenAddr = this.getReqTokenAddr(req.from);
    const quote = await contract.investQuote(
      amount,
      fromTokenAddr,
      req.slippageBps,
      req.deadline
    );
    return {
      ...req,
      feeBps: quote.investFeeBps.map((x: BigNumber) =>
        DecimalBigNumber.fromBN(x, 0)
      ),
      expectedInvestmentAmount: DecimalBigNumber.fromBN(
        quote.quoteData.expectedInvestmentAmount,
        req.investment.receiptToken.decimals
      ),
      minInvestmentAmount: DecimalBigNumber.fromBN(
        quote.quoteData.minInvestmentAmount,
        req.investment.receiptToken.decimals
      ),
      encodedQuote: quote.quoteData,
    };
  }

  async exitQuote(req: ExitQuoteReq): Promise<ExitQuoteResp> {
    return logged(this.exitQuote_(req), {
      label: 'exitQuote',
      req: [req],
      resp: (v) => v,
    });
  }

  private async exitQuote_(req: ExitQuoteReq): Promise<ExitQuoteResp> {
    const provider = this.getProvider(req.investment.chain.id);
    const contract = IOrigamiInvestment__factory.connect(
      req.investment.contractAddress.address,
      provider
    );

    const fromAmount = req.investment.receiptToken.toBN(req.exitAmount);
    const toTokenAddress = this.getReqTokenAddr(req.to);
    const toAmountDecimals = tokenOrNativeAmountDecimals(req.to);

    const quote = await contract.exitQuote(
      fromAmount,
      toTokenAddress,
      req.slippageBps,
      req.deadline
    );

    return {
      ...req,
      feeBps: quote.exitFeeBps.map((x: BigNumber) =>
        DecimalBigNumber.fromBN(x, 0)
      ),
      expectedToAmount: DecimalBigNumber.fromBN(
        quote.quoteData.expectedToTokenAmount,
        toAmountDecimals
      ),
      minToAmount: DecimalBigNumber.fromBN(
        quote.quoteData.minToTokenAmount,
        toAmountDecimals
      ),
      encodedQuote: quote.quoteData,
    };
  }

  getReqTokenAddr(from: TokenOrNative): string {
    return from.kind == 'native'
      ? ethers.constants.AddressZero
      : from.token.config.address;
  }

  every60Secs() {
    // Flush caches every 60 seconds
    this.tokenUsdPrices.clear();
    this.nativeUsdPrices.clear();
  }
}

class SignerApiImpl implements SignerApi {
  chains: VMap<ChainId, Chain>;

  constructor(
    readonly config: ApiConfig,
    readonly signerAddress: string,
    readonly chainId: ChainId,
    readonly signer: Signer
  ) {
    this.chains = new VMap((c) => c.toString());
    for (const c of config.chains) {
      this.chains.put(c.id, c);
    }
  }

  getChain(chainId: ChainId): Chain {
    const chain = this.chains.get(chainId);
    if (!chain) {
      throw new Error(`chain ${chainId} not configured`);
    }
    return chain;
  }

  async invest(req: InvestReq): Promise<InvestResp> {
    return logged(this.invest_(req), {
      label: 'invest',
      req: [req],
      resp: (v) => v,
    });
  }

  private async invest_(req: InvestReq): Promise<InvestResp> {
    const chainId = req.quote.investment.chain.id;
    if (chainId != this.chainId) {
      throw new Error("Signer and investment chain ids don't match");
    }
    const chain = this.getChain(chainId);

    const investmentContract = IOrigamiInvestment__factory.connect(
      req.quote.investment.contractAddress.address,
      this.signer
    );

    if (req.quote.from.kind == 'token') {
      req.onStage && req.onStage({ kind: 'approve' });

      const fromToken = req.quote.from.token;

      const fromTokenContract = IERC20Metadata__factory.connect(
        fromToken.config.address,
        this.signer
      );

      await this.requireTokenApproval(
        fromTokenContract,
        req.quote.investment.contractAddress.address,
        fromToken,
        req.quote.amount
      );
    }

    req.onStage && req.onStage({ kind: 'invest' });

    const feeData = await this.getFeeData();
    const maxFeePerGas = feeData.maxFeePerGas || undefined;
    const maxPriorityFeePerGas = feeData.maxPriorityFeePerGas || undefined;

    let tx: ContractTransaction;
    switch (req.quote.from.kind) {
      case 'native': {
        const amount = req.quote.amount.toBN(chain.nativeCurrency.decimals);
        tx = await investmentContract.investWithNative(
          req.quote.encodedQuote as IOrigamiInvestment.InvestQuoteDataStruct,
          { value: amount }
        );
        break;
      }
      case 'token':
        {
          const quote = req.quote
            .encodedQuote as IOrigamiInvestment.InvestQuoteDataStruct;
          const overrides = {
            maxFeePerGas,
            maxPriorityFeePerGas,
          };
          tx = await investmentContract.investWithToken(quote, overrides);
        }
        break;
    }
    const receipt = await tx.wait();
    const investEvent = first(
      matchEvents(
        receipt?.events || [],
        investmentContract,
        investmentContract.address,
        investmentContract.filters.Invested()
      )
    );

    if (investEvent) {
      const result = {
        investTokenAmount: DecimalBigNumber.fromBN(
          investEvent.args.investmentAmount,
          req.quote.investment.receiptToken.decimals
        ),
        txHash: receipt.transactionHash,
      };
      req.onStage && req.onStage({ kind: 'done', result });
      return result;
    } else {
      throw new Error('investment succeeded, but enable to parse event logs');
    }
  }

  async exit(req: ExitReq): Promise<ExitResp> {
    return logged(this.exit_(req), {
      label: 'exit',
      req: [req],
      resp: (v) => v,
    });
  }

  private async exit_(req: ExitReq): Promise<ExitResp> {
    const chain = req.quote.investment.chain;
    if (chain.id != this.chainId) {
      throw new Error("Signer and investment chain ids don't match");
    }
    const toAmountDecimals = tokenOrNativeAmountDecimals(req.quote.to);

    const investmentContract = IOrigamiInvestment__factory.connect(
      req.quote.investment.contractAddress.address,
      this.signer
    );

    req.onStage && req.onStage({ kind: 'exit' });

    let tx: ContractTransaction;
    switch (req.quote.to.kind) {
      case 'native':
        tx = await investmentContract.exitToNative(
          req.quote.encodedQuote as IOrigamiInvestment.ExitQuoteDataStruct,
          this.signerAddress
        );
        break;
      case 'token':
        tx = await investmentContract.exitToToken(
          req.quote.encodedQuote as IOrigamiInvestment.ExitQuoteDataStruct,
          this.signerAddress
        );
        break;
    }
    const receipt = await tx.wait();
    const exitEvent = first(
      matchEvents(
        receipt?.events || [],
        investmentContract,
        investmentContract.address,
        investmentContract.filters.Exited()
      )
    );
    if (exitEvent) {
      const result = {
        amountOut: DecimalBigNumber.fromBN(
          exitEvent.args.toTokenAmount,
          toAmountDecimals
        ),
        txHash: receipt.transactionHash,
      };
      req.onStage && req.onStage({ kind: 'done', result });
      return result;
    } else {
      throw new Error('investment succeeded, but enable to parse event logs');
    }
  }

  // Check if contract has token allowance and approve if needed
  async requireTokenApproval(
    erc20: IERC20Metadata,
    approvedAddress: string,
    token: Token,
    requiredAmount: DecimalBigNumber
  ) {
    const requiredAmountBN = requiredAmount.toBN(token.decimals);
    const allowance = await erc20.allowance(
      this.signerAddress,
      approvedAddress
    );

    if (allowance.gte(requiredAmountBN)) {
      return;
    }
    const tx = await erc20.approve(approvedAddress, requiredAmountBN);
    await tx.wait();
  }

  async getFeeData() {
    const feeData = await this.signer.getFeeData();
    if (ENABLE_API_LOGS) {
      console.log('api-info', 'signer fee_data', {
        gasPrice:
          feeData.gasPrice &&
          ethers.utils.formatUnits(feeData.gasPrice, 'gwei'),
        lastBaseFeePerGas:
          feeData.lastBaseFeePerGas &&
          ethers.utils.formatUnits(feeData.lastBaseFeePerGas, 'gwei'),
        maxFeePerGas:
          feeData.maxFeePerGas &&
          ethers.utils.formatUnits(feeData.maxFeePerGas, 'gwei'),
        maxPriorityFeePerGas:
          feeData.maxPriorityFeePerGas &&
          ethers.utils.formatUnits(feeData.maxPriorityFeePerGas, 'gwei'),
      });
    }
    return feeData;
  }
}

export interface Notifier {
  handleTransaction(
    tx: Promise<ContractTransaction>,
    messages: NotifierMessages
  ): Promise<ContractReceipt | undefined>;
}

export interface NotifierMessages {
  pending: string;
  success: string;
  error: string;
}

export const SILENT_NOTIFIER: Notifier = {
  handleTransaction: async (tx: Promise<ContractTransaction>, _toastConfig) => {
    return (await tx).wait();
  },
};

const ENABLE_API_LOGS = true;

// log an async request, along with it's response
export async function logged<T>(
  p: Promise<T>,
  params: {
    label: string;
    req?: unknown[];
    resp?(t: T): unknown;
  }
): Promise<T> {
  if (ENABLE_API_LOGS) {
    console.log('api-request', params.label, ...(params.req || []));
  }
  const t = await p;
  if (ENABLE_API_LOGS) {
    const resp = params.resp && params.resp(t);
    console.log('api-response', params.label, params.req, resp);
  }
  return t;
}
