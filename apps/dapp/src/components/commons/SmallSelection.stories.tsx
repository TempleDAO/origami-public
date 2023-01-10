import React, { useState } from 'react';
import { LabelledValue, SmallSelection } from './SmallSelection';

export default {
  title: 'Components/Commons/SmallSelection',
  component: SmallSelection,
};

export const Default = () => {
  const values: LabelledValue<number>[] = [
    ['1%', 0.01],
    ['2%', 0.02],
    ['5%', 0.05],
  ];
  const [value, setValue] = useState<number>(values[0][1]);

  return <SmallSelection values={values} value={value} onChange={setValue} />;
};
