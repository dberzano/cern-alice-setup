/** by Dario Berzano <dario.berzano@gmail.com>
 */

TChain *CreateChainFromFind(TString &path, TString &file, TString &tree,
  Int_t limit = 1e9, Bool_t verbose = kFALSE) {

  TChain *ch = new TChain(tree);
  TString out = gSystem->GetFromPipe( Form("find \"%s/\" -name \"%s\"",
    path.Data(), file.Data()) );
  TObjArray *aptr = out.Tokenize("\r\n");
  TObjArray &a = *aptr;

  if (verbose) Printf("Files to add to the chain: %d", a.GetEntries());

  for (Int_t i=0; i<a.GetEntries() && i<limit; i++) {
    TObjString *os = dynamic_cast<TObjString *>(a[i]);
    TString &s = os->String();
    if (verbose) Printf(">> Adding to chain: %s", s.Data());
    ch->Add(s);
  }

  delete aptr;

  return ch;
}
