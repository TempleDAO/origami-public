import { AutotaskEvent, SentinelConditionRequest, SentinelConditionResponse } from 'defender-autotask-utils';
import { createCommonConfig } from '@/config';
import { autotaskConnect } from '@/connect';
import { getAlertResponse } from './alert-response';
import { TRANSACTION_NAME } from '../glp-auto-compounder/glp-compounder';

const COMMON_CONFIG = createCommonConfig(
    'arbitrum',
    TRANSACTION_NAME,
);

export async function handler(event: AutotaskEvent): Promise<SentinelConditionResponse> {
    const connection = await autotaskConnect(event, COMMON_CONFIG);
    const conditionRequest = event.request!.body as SentinelConditionRequest;
    const events = conditionRequest.events;
    return await getAlertResponse(connection, COMMON_CONFIG, events);
}
