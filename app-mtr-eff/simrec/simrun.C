// #define VERBOSEARGS
// simrun.C
{
  // extract the run and event variables given with
  // --run <x> --event <y> --type <t>
  // where "type" can be "ppMBias" or "pptrg2mu"
  int nrun = 0;
  int nevent = 0;
  int seed = 0;
  char sseed[1024];
  char srun[1024];
  char sevent[1024];
  char type[1024];
  char runOnly[1024];
  sprintf(srun,"");
  sprintf(sevent,"");
  sprintf(runOnly, "");
  for (int i=0; i< gApplication->Argc();i++){
#ifdef VERBOSEARGS
    printf("Arg %d:  %s\n",i,gApplication->Argv(i));
#endif
    if (!(strcmp(gApplication->Argv(i),"--run")))
      nrun = atoi(gApplication->Argv(i+1));
    sprintf(srun,"%d",nrun);
    if (!(strcmp(gApplication->Argv(i),"--event")))
      nevent = atoi(gApplication->Argv(i+1));
    sprintf(sevent,"%d",nevent);
    if (!(strcmp(gApplication->Argv(i),"--type")))
      strcpy(type,gApplication->Argv(i+1));
    if (!(strcmp(gApplication->Argv(i),"--only")))
      strcpy(runOnly,gApplication->Argv(i+1));
  }

  seed = nrun * 100000 + nevent;
  sprintf(sseed,"%d",seed);

  if (seed==0) {
    fprintf(stderr,"!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");
    fprintf(stderr,"!!!!  WARNING! Seeding variable for MC is 0          !!!!\n");
    fprintf(stderr,"!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");
  } else {
    fprintf(stdout,"!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");
    fprintf(stdout,"!!!  MC Seed is %d \n",seed);
    fprintf(stdout,"!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");
  }

  gSystem->Setenv("CONFIG_SEED",sseed);
  gSystem->Setenv("CONFIG_RUN_TYPE",type);
  gSystem->Setenv("DC_RUN",srun);

  TStopwatch sw;

  gSystem->Exec("cp $ALICE_ROOT/.rootrc .rootrc");

  if ((strcmp(runOnly, "") == 0) || (strcmp(runOnly, "sim") == 0)) {
    gSystem->Exec("ls -1 > dir0.txt");
    gSystem->Exec("aliroot -b -q sim.C 2>&1 | tee sim.log");
  }

  if ((strcmp(runOnly, "") == 0) || (strcmp(runOnly, "rec") == 0)) {
    gSystem->Exec("ls -1 > dir1_aftersim.txt");
    gSystem->Exec("aliroot -b -q rec.C 2>&1 | tee rec.log");
  }

  if ((strcmp(runOnly, "") == 0) || (strcmp(runOnly, "ana") == 0)) {
    gSystem->Exec("ls -1 > dir2_afterrec.txt");
    gSystem->Exec("aliroot -b -q runEMT.C 2>&1 | tee emt.log");
  }

  gSystem->Exec("ls -1 > dir3_afterana.txt");

  Printf("*** Global Timer Says ***");
  sw.Print();

}
