void minimalProofTest() {
  TString aliRootVer = "vAN-20141201";
  //TString aliRootVer = "vAN-20150107";
  TString rootVer = "v5-34-08-6";
  TString connStr = "dberzano@alice-caf.cern.ch";

  gSystem->Exec( "rm -f VO*.par 2> /dev/null" );
  gSystem->Exec( Form("./gen_single_par.sh 'VO_ALICE@AliRoot::%s'", aliRootVer.Data()) );

  TProof::Reset(connStr.Data());
  TProof::Mgr(connStr.Data())->SetROOTVersion(Form("VO_ALICE@ROOT::%s", rootVer.Data()));
  TProof::Open(connStr.Data(), "masteronly");
  if (!gProof) return;

  gProof->ClearPackages();
  gProof->UploadPackage( Form("VO_ALICE@AliRoot::%s", aliRootVer.Data()) );
  gProof->EnablePackage( Form("VO_ALICE@AliRoot::%s", aliRootVer.Data()) );
}
