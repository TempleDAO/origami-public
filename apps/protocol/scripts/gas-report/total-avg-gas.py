import os

included_contracts = set()
with open('./scripts/gas-report/in-scope-files.txt') as f:
    for line in f.readlines():
        included_contracts.add(os.path.splitext(os.path.basename(line))[0])

hardhat_total_avg_gas = 0
contract_names = set()
with open('./hardhat-gas-report.txt') as f:
    lines = f.readlines()
    for i in range(9, len(lines), 2):
        # Remove first and last pipe
        line = lines[i][1:-2]
        # cols split by ".", then strip each cell
        cells = list(map(lambda cell: cell.strip(), line.split("·")))
        contract_name, method_name = cells[0:2]

        if contract_name == "Deployments":
            break
        if contract_name not in included_contracts:
            continue

        avg_gas = int(cells[4])
        hardhat_total_avg_gas += avg_gas
        contract_names.add(contract_name)
        
forge_total_avg_gas = 0
with open('./forge-gas-report.txt') as f:
    index = 0
    lines = f.readlines()
    while index < len(lines):
        line = lines[index]

        if (" contract |") not in line:
            index += 1
            continue
        
        contract_name = line.split("|")[1].replace(" contract", "")
        contract_name = os.path.splitext(os.path.basename(contract_name))[0]

        index += 1
        if contract_name not in included_contracts:
            continue
        contract_names.add(contract_name)

        index += 4
        line = lines[index]
        while " contract |" not in line:
            if "| " in line:
                cells = list(map(lambda cell: cell.strip(), line[1:-2].split("|")))
                avg_gas = int(cells[2])
                forge_total_avg_gas += avg_gas
            index += 1
            line = lines[index]

print("Hardhat total avg: ", hardhat_total_avg_gas)
print("Forge total avg: ", forge_total_avg_gas)
print("-----------------------------")
print("Total of averages: ", hardhat_total_avg_gas+forge_total_avg_gas)
        
# print(sorted(list(contract_names)))
