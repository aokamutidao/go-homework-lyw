const solc = require('solc');
const fs = require('fs');

// Read the Solidity source code
const sourceCode = fs.readFileSync('Counter.sol', 'utf8');

console.log('Using solc version:', solc.version());

// Build solc standard input (key: specify evm.bytecode in outputSelection)
const input = {
  language: 'Solidity',
  sources: {
    'Counter.sol': {
      content: sourceCode
    }
  },
  settings: {
    outputSelection: {
      '*': {
        '*': ['abi', 'evm.bytecode'] // Explicitly require ABI and bytecode
      }
    }
  }
};

// Compile using standard compile method
const output = JSON.parse(solc.compile(JSON.stringify(input)));

console.log('Output keys:', Object.keys(output));

// Check for errors
if (output.errors) {
  output.errors.forEach(err => {
    console.error(err.formattedMessage);
  });
}

// Extract contract output
const contractName = 'Counter';
const contractOutput = output.contracts['Counter.sol'][contractName];

if (contractOutput) {
  console.log('Contract keys:', Object.keys(contractOutput));

  // Write the ABI
  fs.writeFileSync('Counter.abi', JSON.stringify(contractOutput.abi, null, 2));

  // Write the bytecode
  fs.writeFileSync('Counter.bin', contractOutput.evm.bytecode.object);

  console.log('Compilation successful!');
  console.log('ABI written to Counter.abi');
  console.log('Bytecode written to Counter.bin');
  console.log('Bytecode length:', contractOutput.evm.bytecode.object.length);
} else {
  console.log('Contract not found in output');
  console.log('Available contracts:', Object.keys(output.contracts));
}
