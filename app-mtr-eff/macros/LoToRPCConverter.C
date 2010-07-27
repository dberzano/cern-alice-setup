void LoToRPCConverter() {

  ifstream is("LocalBoardToRPCMapping.txt");

  if (!is) {
    Printf("Can't open file \"LocalBoardToRPCMapping.txt\".");
    return;
  }

  char buf[1000];
  TPMERegexp lineRe("([0-9]+) \\| {(.+)}");
  Int_t rpcCount = 0;
  vector<Int_t> los[18];

  while (is.getline(buf, 1000)) {
    Int_t nMatches = lineRe.Match(buf);
    if (nMatches == 3) {
      Int_t nRpc = lineRe[1].Atoi();
      TString arr = lineRe[2];
      TObjArray *tokens = arr.Tokenize(",");
      TIter i(tokens);
      TObject *o;
      TObjString *tok;
      while (( tok = dynamic_cast<TObjString *>(i.Next()) )) {
        TString ts = tok->GetString();
        Int_t lo = ts.Atoi();
        los[nRpc].push_back(lo);
      }

      // Mini sort (not efficient but who cares?)
      for (Int_t j=0; j<los[nRpc].size()-1; j++) {
        for (Int_t k=j+1; k<los[nRpc].size(); k++) {
          if (los[nRpc][j] > los[nRpc][k]) {
            los[nRpc][j] = los[nRpc][j] ^ los[nRpc][k];
            los[nRpc][k] = los[nRpc][j] ^ los[nRpc][k];
            los[nRpc][j] = los[nRpc][j] ^ los[nRpc][k];
          }
        }
      }

      rpcCount++;
    }
  }

  is.close();

  // Print the list as a single array
  printf("rpc[234] = { ");
  for (Int_t j=0; j<18; j++) {
    for (Int_t k=0; k<los[j].size(); k++) {
      printf("%d", los[j][k]);
      if ((j==17) && (k == los[j].size()-1)) printf(" };\n");
      else printf(", ");
    }
  }

  // Print num. of elements
  printf("nel[18] = { ");
  for (Int_t j=0; j<18; j++) {
    printf("%d", los[j].size());
    if (j==17) printf(" };\n");
    else printf(", ");
  }

  // Now we print out the results
  //Printf("/* === RPC number from Local Board === */");
  //Printf("/* code to find index, and save it to idx */");
  //Int_t gc = 0;
  //for (Int_t j=0; j<18; j++) {
  //  Int_t lb = gc;
  //  Int_t hb = (gc+=los[j].size())-1;
  //  Printf("%sif ((idx >= %d) && (idx <= %d)) rpc = %d;", (j?"else ":""),
  //    lb, hb, j);
  //
  //}
}
