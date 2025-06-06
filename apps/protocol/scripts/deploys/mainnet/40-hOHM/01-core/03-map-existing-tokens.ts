import {
  mine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';
import * as fs from 'fs';
import path from 'path';

async function main() {
  const { INSTANCES } = await getDeployContext(__dirname);
  const entries: {[token: string]: string} = JSON.parse(fs.readFileSync(path.join(__dirname, "./v3-token-mappings.json"), 'utf-8'));
  const mappings = Object.entries(entries).map((v) => ({token: v[0], fnCalldata: v[1]}));
  await mine(INSTANCES.CORE.TOKEN_PRICES.V4.setTokenPriceFunctions(mappings));
}

runAsyncMain(main);
