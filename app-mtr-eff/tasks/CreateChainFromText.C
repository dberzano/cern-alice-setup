/** by Dario Berzano <dario.berzano@gmail.com>
 */

TChain *CreateChainFromText(TString file, TString &tree,
  Bool_t verbose = kFALSE) {

  Printf("porco il dio di merda cazzo");

  if (verbose) Printf("Reading list from %s", file.Data());

  TChain *ch = new TChain(tree);

  ifstream is(file.Data());
  const char buf[1000];

  while (is.getline(buf, 1000)) {
    if (*buf == '\0') continue;
    if (verbose) Printf(">> Adding to chain: %s", buf);
    ch->Add(buf);
  }

  is.close();

  return ch;
}
