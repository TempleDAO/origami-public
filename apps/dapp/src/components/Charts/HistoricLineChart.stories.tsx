import { HistoricLineChart } from '.';
import { DepositGridItem } from '@/pages/deposit/DepositGrid';
import { ready } from '@/utils/loading-value';
import { DecimalBigNumber } from '@/utils/decimal-big-number';
import { arbitrum, getHistory } from '@/api/test';
import { action } from '@storybook/addon-actions';

export default {
  title: 'Components/Charts/HistoricLineChart',
  component: HistoricLineChart,
};

const dayTestValues = ready([
  {
    x: 1681279200000,
    y: 0.052000000000000005,
  },
  {
    x: 1681282800000,
    y: 0.052000000000000005,
  },
  {
    x: 1681286400000,
    y: 0.052000000000000005,
  },
  {
    x: 1681290000000,
    y: 0.052000000000000005,
  },
  {
    x: 1681293600000,
    y: 0.052000000000000005,
  },
  {
    x: 1681297200000,
    y: 0.052000000000000005,
  },
  {
    x: 1681300800000,
    y: 0.052000000000000005,
  },
  {
    x: 1681304400000,
    y: 0.052000000000000005,
  },
  {
    x: 1681308000000,
    y: 0.052000000000000005,
  },
  {
    x: 1681311600000,
    y: 0.052000000000000005,
  },
  {
    x: 1681315200000,
    y: 0.052000000000000005,
  },
  {
    x: 1681318800000,
    y: 0.052000000000000005,
  },
  {
    x: 1681322400000,
    y: 0.052000000000000005,
  },
  {
    x: 1681326000000,
    y: 0.052000000000000005,
  },
  {
    x: 1681329600000,
    y: 0.052000000000000005,
  },
  {
    x: 1681333200000,
    y: 0.052000000000000005,
  },
  {
    x: 1681336800000,
    y: 0.045700000000000005,
  },
  {
    x: 1681340400000,
    y: 0.045700000000000005,
  },
  {
    x: 1681344000000,
    y: 0.045700000000000005,
  },
  {
    x: 1681347600000,
    y: 0.045700000000000005,
  },
  {
    x: 1681351200000,
    y: 0.045700000000000005,
  },
  {
    x: 1681354800000,
    y: 0.045700000000000005,
  },
  {
    x: 1681358400000,
    y: 0.045700000000000005,
  },
  {
    x: 1681362000000,
    y: 0.045700000000000005,
  },
]);
const weekTestValues = ready([
  {
    x: 1680760800000,
    y: 0.1225,
  },
  {
    x: 1680764400000,
    y: 0.1225,
  },
  {
    x: 1680768000000,
    y: 0.1225,
  },
  {
    x: 1680771600000,
    y: 0.1225,
  },
  {
    x: 1680775200000,
    y: 0.1225,
  },
  {
    x: 1680778800000,
    y: 0.1225,
  },
  {
    x: 1680782400000,
    y: 0.1225,
  },
  {
    x: 1680786000000,
    y: 0.1225,
  },
  {
    x: 1680789600000,
    y: 0.1225,
  },
  {
    x: 1680793200000,
    y: 0.1225,
  },
  {
    x: 1680796800000,
    y: 0.1225,
  },
  {
    x: 1680800400000,
    y: 0.1225,
  },
  {
    x: 1680804000000,
    y: 0.1225,
  },
  {
    x: 1680807600000,
    y: 0.1225,
  },
  {
    x: 1680811200000,
    y: 0.1225,
  },
  {
    x: 1680814800000,
    y: 0.1225,
  },
  {
    x: 1680818400000,
    y: 0.10529999999999999,
  },
  {
    x: 1680822000000,
    y: 0.10529999999999999,
  },
  {
    x: 1680825600000,
    y: 0.10529999999999999,
  },
  {
    x: 1680829200000,
    y: 0.10529999999999999,
  },
  {
    x: 1680832800000,
    y: 0.10529999999999999,
  },
  {
    x: 1680836400000,
    y: 0.10529999999999999,
  },
  {
    x: 1680840000000,
    y: 0.10529999999999999,
  },
  {
    x: 1680843600000,
    y: 0.10529999999999999,
  },
  {
    x: 1680847200000,
    y: 0.10529999999999999,
  },
  {
    x: 1680850800000,
    y: 0.10529999999999999,
  },
  {
    x: 1680854400000,
    y: 0.10529999999999999,
  },
  {
    x: 1680858000000,
    y: 0.10529999999999999,
  },
  {
    x: 1680861600000,
    y: 0.10529999999999999,
  },
  {
    x: 1680865200000,
    y: 0.10529999999999999,
  },
  {
    x: 1680868800000,
    y: 0.10529999999999999,
  },
  {
    x: 1680872400000,
    y: 0.10529999999999999,
  },
  {
    x: 1680876000000,
    y: 0.10529999999999999,
  },
  {
    x: 1680879600000,
    y: 0.10529999999999999,
  },
  {
    x: 1680883200000,
    y: 0.10529999999999999,
  },
  {
    x: 1680886800000,
    y: 0.10529999999999999,
  },
  {
    x: 1680890400000,
    y: 0.10529999999999999,
  },
  {
    x: 1680894000000,
    y: 0.10529999999999999,
  },
  {
    x: 1680897600000,
    y: 0.10529999999999999,
  },
  {
    x: 1680901200000,
    y: 0.10529999999999999,
  },
  {
    x: 1680904800000,
    y: 0.0909,
  },
  {
    x: 1680908400000,
    y: 0.0909,
  },
  {
    x: 1680912000000,
    y: 0.0909,
  },
  {
    x: 1680915600000,
    y: 0.0909,
  },
  {
    x: 1680919200000,
    y: 0.0909,
  },
  {
    x: 1680922800000,
    y: 0.0909,
  },
  {
    x: 1680926400000,
    y: 0.0909,
  },
  {
    x: 1680930000000,
    y: 0.0909,
  },
  {
    x: 1680933600000,
    y: 0.0909,
  },
  {
    x: 1680937200000,
    y: 0.0909,
  },
  {
    x: 1680940800000,
    y: 0.0909,
  },
  {
    x: 1680944400000,
    y: 0.0909,
  },
  {
    x: 1680948000000,
    y: 0.0909,
  },
  {
    x: 1680951600000,
    y: 0.0909,
  },
  {
    x: 1680955200000,
    y: 0.0909,
  },
  {
    x: 1680958800000,
    y: 0.0909,
  },
  {
    x: 1680962400000,
    y: 0.0909,
  },
  {
    x: 1680966000000,
    y: 0.0909,
  },
  {
    x: 1680969600000,
    y: 0.0909,
  },
  {
    x: 1680973200000,
    y: 0.0909,
  },
  {
    x: 1680976800000,
    y: 0.0909,
  },
  {
    x: 1680980400000,
    y: 0.0909,
  },
  {
    x: 1680984000000,
    y: 0.0909,
  },
  {
    x: 1680987600000,
    y: 0.0909,
  },
  {
    x: 1680991200000,
    y: 0.0787,
  },
  {
    x: 1680994800000,
    y: 0.0787,
  },
  {
    x: 1680998400000,
    y: 0.0787,
  },
  {
    x: 1681002000000,
    y: 0.0787,
  },
  {
    x: 1681005600000,
    y: 0.0787,
  },
  {
    x: 1681009200000,
    y: 0.0787,
  },
  {
    x: 1681012800000,
    y: 0.0787,
  },
  {
    x: 1681016400000,
    y: 0.0787,
  },
  {
    x: 1681020000000,
    y: 0.0787,
  },
  {
    x: 1681023600000,
    y: 0.0787,
  },
  {
    x: 1681027200000,
    y: 0.0787,
  },
  {
    x: 1681030800000,
    y: 0.0787,
  },
  {
    x: 1681034400000,
    y: 0.0787,
  },
  {
    x: 1681038000000,
    y: 0.0787,
  },
  {
    x: 1681041600000,
    y: 0.0787,
  },
  {
    x: 1681045200000,
    y: 0.0787,
  },
  {
    x: 1681048800000,
    y: 0.0787,
  },
  {
    x: 1681052400000,
    y: 0.0787,
  },
  {
    x: 1681056000000,
    y: 0.0787,
  },
  {
    x: 1681059600000,
    y: 0.0787,
  },
  {
    x: 1681063200000,
    y: 0.0787,
  },
  {
    x: 1681066800000,
    y: 0.0787,
  },
  {
    x: 1681070400000,
    y: 0.0787,
  },
  {
    x: 1681074000000,
    y: 0.0787,
  },
  {
    x: 1681077600000,
    y: 0.0683,
  },
  {
    x: 1681081200000,
    y: 0.0683,
  },
  {
    x: 1681084800000,
    y: 0.0683,
  },
  {
    x: 1681088400000,
    y: 0.0683,
  },
  {
    x: 1681092000000,
    y: 0.0683,
  },
  {
    x: 1681095600000,
    y: 0.0683,
  },
  {
    x: 1681099200000,
    y: 0.0683,
  },
  {
    x: 1681102800000,
    y: 0.0683,
  },
  {
    x: 1681106400000,
    y: 0.0683,
  },
  {
    x: 1681110000000,
    y: 0.0683,
  },
  {
    x: 1681113600000,
    y: 0.0683,
  },
  {
    x: 1681117200000,
    y: 0.0683,
  },
  {
    x: 1681120800000,
    y: 0.0683,
  },
  {
    x: 1681124400000,
    y: 0.0683,
  },
  {
    x: 1681128000000,
    y: 0.0683,
  },
  {
    x: 1681131600000,
    y: 0.0683,
  },
  {
    x: 1681135200000,
    y: 0.0683,
  },
  {
    x: 1681138800000,
    y: 0.0683,
  },
  {
    x: 1681142400000,
    y: 0.0683,
  },
  {
    x: 1681146000000,
    y: 0.0683,
  },
  {
    x: 1681149600000,
    y: 0.0683,
  },
  {
    x: 1681153200000,
    y: 0.0683,
  },
  {
    x: 1681156800000,
    y: 0.0683,
  },
  {
    x: 1681160400000,
    y: 0.0683,
  },
  {
    x: 1681164000000,
    y: 0.0594,
  },
  {
    x: 1681167600000,
    y: 0.0594,
  },
  {
    x: 1681171200000,
    y: 0.0594,
  },
  {
    x: 1681174800000,
    y: 0.0594,
  },
  {
    x: 1681178400000,
    y: 0.0594,
  },
  {
    x: 1681182000000,
    y: 0.0594,
  },
  {
    x: 1681185600000,
    y: 0.0594,
  },
  {
    x: 1681189200000,
    y: 0.0594,
  },
  {
    x: 1681192800000,
    y: 0.0594,
  },
  {
    x: 1681196400000,
    y: 0.0594,
  },
  {
    x: 1681200000000,
    y: 0.0594,
  },
  {
    x: 1681203600000,
    y: 0.0594,
  },
  {
    x: 1681207200000,
    y: 0.0594,
  },
  {
    x: 1681210800000,
    y: 0.0594,
  },
  {
    x: 1681214400000,
    y: 0.0594,
  },
  {
    x: 1681218000000,
    y: 0.0594,
  },
  {
    x: 1681221600000,
    y: 0.0594,
  },
  {
    x: 1681225200000,
    y: 0.0594,
  },
  {
    x: 1681228800000,
    y: 0.0594,
  },
  {
    x: 1681232400000,
    y: 0.0594,
  },
  {
    x: 1681236000000,
    y: 0.0594,
  },
  {
    x: 1681239600000,
    y: 0.0594,
  },
  {
    x: 1681243200000,
    y: 0.0594,
  },
  {
    x: 1681246800000,
    y: 0.0594,
  },
  {
    x: 1681250400000,
    y: 0.052000000000000005,
  },
  {
    x: 1681254000000,
    y: 0.052000000000000005,
  },
  {
    x: 1681257600000,
    y: 0.052000000000000005,
  },
  {
    x: 1681261200000,
    y: 0.052000000000000005,
  },
  {
    x: 1681264800000,
    y: 0.052000000000000005,
  },
  {
    x: 1681268400000,
    y: 0.052000000000000005,
  },
  {
    x: 1681272000000,
    y: 0.052000000000000005,
  },
  {
    x: 1681275600000,
    y: 0.052000000000000005,
  },
  {
    x: 1681279200000,
    y: 0.052000000000000005,
  },
  {
    x: 1681282800000,
    y: 0.052000000000000005,
  },
  {
    x: 1681286400000,
    y: 0.052000000000000005,
  },
  {
    x: 1681290000000,
    y: 0.052000000000000005,
  },
  {
    x: 1681293600000,
    y: 0.052000000000000005,
  },
  {
    x: 1681297200000,
    y: 0.052000000000000005,
  },
  {
    x: 1681300800000,
    y: 0.052000000000000005,
  },
  {
    x: 1681304400000,
    y: 0.052000000000000005,
  },
  {
    x: 1681308000000,
    y: 0.052000000000000005,
  },
  {
    x: 1681311600000,
    y: 0.052000000000000005,
  },
  {
    x: 1681315200000,
    y: 0.052000000000000005,
  },
  {
    x: 1681318800000,
    y: 0.052000000000000005,
  },
  {
    x: 1681322400000,
    y: 0.052000000000000005,
  },
  {
    x: 1681326000000,
    y: 0.052000000000000005,
  },
  {
    x: 1681329600000,
    y: 0.052000000000000005,
  },
  {
    x: 1681333200000,
    y: 0.052000000000000005,
  },
  {
    x: 1681336800000,
    y: 0.045700000000000005,
  },
  {
    x: 1681340400000,
    y: 0.045700000000000005,
  },
  {
    x: 1681344000000,
    y: 0.045700000000000005,
  },
  {
    x: 1681347600000,
    y: 0.045700000000000005,
  },
  {
    x: 1681351200000,
    y: 0.045700000000000005,
  },
  {
    x: 1681354800000,
    y: 0.045700000000000005,
  },
  {
    x: 1681358400000,
    y: 0.045700000000000005,
  },
  {
    x: 1681362000000,
    y: 0.045700000000000005,
  },
]);
const monthTestValues = ready([
  {
    x: 1678838400000,
    y: 0.43270000000000003,
  },
  {
    x: 1678924800000,
    y: 0.4867,
  },
  {
    x: 1679011200000,
    y: 0.5072,
  },
  {
    x: 1679097600000,
    y: 0.5243,
  },
  {
    x: 1679184000000,
    y: 0.5243,
  },
  {
    x: 1679270400000,
    y: 0.5529999999999999,
  },
  {
    x: 1679356800000,
    y: 0.0032,
  },
  {
    x: 1679443200000,
    y: 0.09300000000000001,
  },
  {
    x: 1679529600000,
    y: 0.6686,
  },
  {
    x: 1679616000000,
    y: 0.6057,
  },
  {
    x: 1679702400000,
    y: 0.5540999999999999,
  },
  {
    x: 1679788800000,
    y: 0.5111,
  },
  {
    x: 1679875200000,
    y: 0.5111,
  },
  {
    x: 1679961600000,
    y: 0.44439999999999996,
  },
  {
    x: 1680048000000,
    y: 0.4152,
  },
  {
    x: 1680134400000,
    y: 0.3568,
  },
  {
    x: 1680220800000,
    y: 0.2916,
  },
  {
    x: 1680307200000,
    y: 0.2466,
  },
  {
    x: 1680393600000,
    y: 0.2036,
  },
  {
    x: 1680480000000,
    y: 0.1679,
  },
  {
    x: 1680566400000,
    y: 0.1439,
  },
  {
    x: 1680652800000,
    y: 0.1225,
  },
  {
    x: 1680739200000,
    y: 0.10529999999999999,
  },
  {
    x: 1680825600000,
    y: 0.0909,
  },
  {
    x: 1680912000000,
    y: 0.0787,
  },
  {
    x: 1680998400000,
    y: 0.0683,
  },
  {
    x: 1681084800000,
    y: 0.0594,
  },
  {
    x: 1681171200000,
    y: 0.052000000000000005,
  },
  {
    x: 1681257600000,
    y: 0.045700000000000005,
  },
  {
    x: 1681344000000,
    y: 0.045700000000000005,
  },
]);
const allTestValues = ready([
  {
    x: 1678147200000,
    y: 0.4422,
  },
  {
    x: 1678233600000,
    y: 0.1753,
  },
  {
    x: 1678320000000,
    y: 0.1399,
  },
  {
    x: 1678406400000,
    y: 0.18539999999999998,
  },
  {
    x: 1678492800000,
    y: 0.18539999999999998,
  },
  {
    x: 1678579200000,
    y: 0.3602,
  },
  {
    x: 1678665600000,
    y: 0.3602,
  },
  {
    x: 1678752000000,
    y: 0.43270000000000003,
  },
  {
    x: 1678838400000,
    y: 0.43270000000000003,
  },
  {
    x: 1678924800000,
    y: 0.4867,
  },
  {
    x: 1679011200000,
    y: 0.5072,
  },
  {
    x: 1679097600000,
    y: 0.5243,
  },
  {
    x: 1679184000000,
    y: 0.5243,
  },
  {
    x: 1679270400000,
    y: 0.5529999999999999,
  },
  {
    x: 1679356800000,
    y: 0.0032,
  },
  {
    x: 1679443200000,
    y: 0.09300000000000001,
  },
  {
    x: 1679529600000,
    y: 0.6686,
  },
  {
    x: 1679616000000,
    y: 0.6057,
  },
  {
    x: 1679702400000,
    y: 0.5540999999999999,
  },
  {
    x: 1679788800000,
    y: 0.5111,
  },
  {
    x: 1679875200000,
    y: 0.5111,
  },
  {
    x: 1679961600000,
    y: 0.44439999999999996,
  },
  {
    x: 1680048000000,
    y: 0.4152,
  },
  {
    x: 1680134400000,
    y: 0.3568,
  },
  {
    x: 1680220800000,
    y: 0.2916,
  },
  {
    x: 1680307200000,
    y: 0.2466,
  },
  {
    x: 1680393600000,
    y: 0.2036,
  },
  {
    x: 1680480000000,
    y: 0.1679,
  },
  {
    x: 1680566400000,
    y: 0.1439,
  },
  {
    x: 1680652800000,
    y: 0.1225,
  },
  {
    x: 1680739200000,
    y: 0.10529999999999999,
  },
  {
    x: 1680825600000,
    y: 0.0909,
  },
  {
    x: 1680912000000,
    y: 0.0787,
  },
  {
    x: 1680998400000,
    y: 0.0683,
  },
  {
    x: 1681084800000,
    y: 0.0594,
  },
  {
    x: 1681171200000,
    y: 0.052000000000000005,
  },
  {
    x: 1681257600000,
    y: 0.045700000000000005,
  },
  {
    x: 1681344000000,
    y: 0.045700000000000005,
  },
]);

export const Default = () => {
  return (
    <HistoricLineChart
      chartData={dayTestValues}
      selectedInterval={'day'}
      histSeries={'apy'}
      legendFormatter={() => `${gmx().name} % APY day`}
    />
  );
};

export const Week = () => {
  return (
    <HistoricLineChart
      chartData={weekTestValues}
      selectedInterval={'week'}
      histSeries={'apy'}
      legendFormatter={() => `${gmx().name} % APY week`}
    />
  );
};

export const Month = () => {
  return (
    <HistoricLineChart
      chartData={monthTestValues}
      selectedInterval={'month'}
      histSeries={'apy'}
      legendFormatter={() => `${gmx().name} % APY month`}
    />
  );
};

export const All = () => {
  return (
    <HistoricLineChart
      chartData={allTestValues}
      selectedInterval={'all'}
      histSeries={'apy'}
      legendFormatter={() => `${gmx().name} % APY all`}
    />
  );
};

function gmx(): DepositGridItem {
  return {
    icon: 'gmx',
    name: 'GMX',
    description: 'Utility token for the GMX protocol',
    apy: ready(0.121),
    tvl: ready(4860000),
    tokenPrice: ready(DecimalBigNumber.parseUnits('1.67', 2)),
    chain: arbitrum(),
    info: poolInfo('GMX'),
    tokenAddr: '0xovGMX',
    receiptToken: 'ovGMX',
    reserveToken: 'oGMX',
    getHistory,
    onInvest: async () => action('onInvest gmx')(),
  };
}

function poolInfo(s: string) {
  return `
  Info on the ${s} pool. Lorem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industry's standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book.
  `;
}
