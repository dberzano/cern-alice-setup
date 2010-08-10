#ifndef ALIANALYSISTASKAPPMTREFF_H
#define ALIANALYSISTASKAPPMTREFF_H

// ROOT includes
#include <TH1F.h>
#include <TChain.h>
#include <TTree.h>
#include <TFile.h>
#include <TRandom3.h>
#include <TString.h>
#include <TClonesArray.h>

// AliRoot includes
#include "AliLog.h"
#include "AliAnalysisManager.h"
#include "AliAnalysisTask.h"
#include "AliCDBManager.h"
#include "AliCDBEntry.h"
#include "AliESDEvent.h"
#include "AliESDInputHandler.h"
#include "AliESDMuonTrack.h"
#include "AliMUONTriggerChamberEfficiency.h"
#include "AliMUONTriggerEfficiencyCells.h"
#include "AliMUONESDInterface.h"
#include "AliMUONConstants.h"
#include "AliMUONCDB.h"
#include "AliMCEventHandler.h"
#include "AliMCParticle.h"
#include "AliMCEvent.h"

////////////////////////////////////////////////////////////////////////////////
// Definiton of the Event class. This is a simple container class that contains
// a TClonesArray of tracks for a given event.
////////////////////////////////////////////////////////////////////////////////
class Event : public TObject {

public: 

  Event(Int_t evNum = -1, const char *fileName = "") :
    fTracks(0x0), fFileName(fileName), fEvNum(evNum) {};
  virtual ~Event() { if (fTracks) delete fTracks; }

  virtual TClonesArray *GetTracks() { return fTracks; }
  virtual const Char_t *GetFileName() { return fFileName.Data(); }
  virtual Int_t GetEventNumber() { return fEvNum; }

protected:

  TClonesArray *fTracks;
  TString       fFileName;
  Int_t         fEvNum;

  ClassDef(Event, 1);

};

////////////////////////////////////////////////////////////////////////////////
// It inherits from Event and it holds a TClonesArray of AliESDMuonTrack
////////////////////////////////////////////////////////////////////////////////
class EventEsd : public Event {

  public:

    EventEsd(Int_t evNum = -1, const char *fileName = "") :
      Event(evNum, fileName) {
      fTracks = new TClonesArray("AliESDMuonTrack", 10);
    }

  ClassDef(EventEsd, 1);

};

////////////////////////////////////////////////////////////////////////////////
// It inherits from Event and it holds a TClonesArray of AliESDMuonTrack
////////////////////////////////////////////////////////////////////////////////
class EventMc : public Event {

  public:

    EventMc(Int_t evNum = -1, const char *fileName = "") :
      Event(evNum, fileName) {
      fTracks = new TClonesArray("TParticle", 10);
    }

  ClassDef(EventMc, 1);

};

////////////////////////////////////////////////////////////////////////////////
// Definiton of the analysis task that extracts muon tracks from an ESD. The
// analysis task can also be configured to mark some tracks as triggered or not
// triggered, if we want to apply the efficiency correction at ESD level. For
// this procedure, the OCDB is used, and the map of efficiencies should be put
// in the custom specific storage for the OCDB
////////////////////////////////////////////////////////////////////////////////
class AliAnalysisTaskAppMtrEff : public AliAnalysisTask {

  public:

    // See http://aliweb.cern.ch/Offline/Activities/Analysis/AnalysisFramework/
    // index.html (we should not DefineInput/Output in the default constructor)
    AliAnalysisTaskAppMtrEff() {};

    AliAnalysisTaskAppMtrEff(const char *name,
      Bool_t applyEfficiencies = kFALSE, Int_t runNum = -1,
      const char *ocdbTrigChEff = NULL);
    virtual ~AliAnalysisTaskAppMtrEff();

    virtual void CreateOutputObjects();
    virtual void Exec(Option_t *opt);
    virtual void Terminate(Option_t *opt);
    virtual void ConnectInputData(Option_t *opt);

  protected:

    static Double_t Rapidity(Double_t e, Double_t pz);

  private:

    TTree        *fTreeMc;      //! Output tree for generated particles
    TTree        *fTreeRec;     //! Output tree for reconstructed events

    EventMc      *fEventMc;     //! Output Monte Carlo event
    EventEsd     *fEventEsd;    //! Output reconstructed event

    TList        *fHistoList;   //! List that containts output histos
    TH1F         *fHistoPt;     //! Output test Pt distro

    Float_t      *fEffRpc;      //! Array of efficiencies per RPC
    Float_t      *fEffCh;       //! Array of efficiencies per chamber

    Bool_t        fApplyEff;    //! If kTRUE, apply effs "a posteriori"

    AliESDEvent  *fCurEsdEvt;   //! Points to the current ESD event
    AliMCEvent   *fCurMcEvt;    //! Points to the current MC event

    AliMUONTriggerChamberEfficiency *fTrigChEff;  //! Handler of OCDB ch. effs

    // Copy constructor and assignment operator are disabled for this class
    AliAnalysisTaskAppMtrEff(const AliAnalysisTaskAppMtrEff &);
    AliAnalysisTaskAppMtrEff& operator=(
      const AliAnalysisTaskAppMtrEff&);
 
    ClassDef(AliAnalysisTaskAppMtrEff, 1);
};

#endif // ALIANALYSISTASKAPPMTREFF_H
