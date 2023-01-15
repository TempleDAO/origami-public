import { useEffect, useState } from 'react';

export function useMediaQuery(query: string): boolean {
  const queryFormatted = `(min-width: ${query})`;

  const getMatches = (query: string): boolean => {
    if (typeof window !== 'undefined') {
      return window.matchMedia(query).matches;
    }
    return false;
  };

  const [matches, setMatches] = useState<boolean>(getMatches(queryFormatted));

  function handleChange() {
    setMatches(getMatches(queryFormatted));
  }

  useEffect(() => {
    const matchMedia = window.matchMedia(queryFormatted);
    handleChange();
    matchMedia.addEventListener('change', handleChange);
    return () => {
      matchMedia.removeEventListener('change', handleChange);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query]);

  return matches;
}
