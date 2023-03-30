type MarkdownLink = {
  text: string;
  url: string;
};

export function extractStringLinks(textToParse: string) {
  const regex = /\[([^\]]+)\]\((https?:\/\/[^)]+)\)/g;

  let match: RegExpExecArray | null;
  let prevEndIndex = 0;
  const substrings: string[] = [];
  const links: MarkdownLink[] = [];

  while ((match = regex.exec(textToParse)) !== null) {
    // Save the unmatched part of the text
    substrings.push(textToParse.slice(prevEndIndex, match.index));

    // Add the link object to the array
    links.push({ text: match[1], url: match[2] });

    // Update the end index for the next iteration
    prevEndIndex = match.index + match[0].length;
  }

  // Add the last part of the text after the last matched link
  substrings.push(textToParse.slice(prevEndIndex));

  return { substrings, links };
}
