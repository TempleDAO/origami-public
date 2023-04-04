type TokenLabelMap = Record<string, string>;

export const tokenLabelMap: TokenLabelMap = {
  // Intentionally aliased as just 'GLP' to avoid user confusion.
  // 'staked GLP' is the GMX helper contract used to transfer a user's GLP -> Origami
  // However it isn't the actual ERC20 that the user holds.
  sGLP: 'GLP (sGLP)',
};
