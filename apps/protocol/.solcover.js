module.exports = {
    skipFiles: [
        'test',  // Test contracts including external contracts, don't care about coverage.
        'interfaces', // Interfaces aren't tested anyway - so all just come up green
    ],
    modifierWhitelist: [
        'nonReentrant', // Tests don't always cover the 'else' branch - ie when reentrancy is hit
        'initializer',  // OZ Initializable for UUPS Proxy
    ],
  };