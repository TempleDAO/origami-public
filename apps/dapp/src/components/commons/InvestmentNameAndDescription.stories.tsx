import { InvestmentNameAndDescription } from './InvestmentNameAndDescription';

export default {
  title: 'Components/Commons/InvestmentNameAndDescription',
  component: InvestmentNameAndDescription,
};

export const NameAndDescriptionWithLink = () => (
  <InvestmentNameAndDescription
    name="ovToken"
    description="Lets make this token great again"
    tokenExplorerUrl="http://ovToken.com"
  />
);
