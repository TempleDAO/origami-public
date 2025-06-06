import * as fs from 'fs';
import path from "path";
import { getDeployContext } from "../../deploy-context";
import { runAsyncMain } from '../../../helpers';

async function main() {
  const { INSTANCES } = await getDeployContext(__dirname);

  const filter = INSTANCES.CORE.TOKEN_PRICES.V3.filters.TokenPriceFunctionSet();
  const events = await INSTANCES.CORE.TOKEN_PRICES.V3.queryFilter(
    filter,
    20310517, // Creation block for V3
  );

  const results = new Map<string, string>(); 
  events.forEach(event => results.set(event.args.token, event.args.fnCalldata));
  
  fs.writeFileSync(
    path.join(__dirname, "./v3-token-mappings.json"),
    JSON.stringify(Object.fromEntries(results), null, 2)
  );
}

runAsyncMain(main);
