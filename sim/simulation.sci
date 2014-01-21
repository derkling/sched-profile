clear
global SkedData
SkedData = struct('SP_Tr',0,'alfa',[],'alfaBlock',[],'alfaBlocko',[],...
                  'krr',0,'zrr',0,'kpi',0,'bmin',0,'bmax',0,...
                  'SP_Tp',[],'eTp',[],'eTr',0,'eTro',0,'bc',0,'bco',0,...
                  'b',[],'bo',[],'Tp',[],'Tr',0,'t',0,...
                  'Tpacc',[],'Ton',[],'Toff',[],'sleepPoint',[],...
                  'bRemaining',[],'cpuRemaining',[],'saturated',[]);
global SimRes
SimRes   = struct('Ntot',0,...
                  'NfirstCur',0,....
                  'mt',[],...
                  'mSP_Tr',[],'mTr',[],...
                  'mSP_Tp',[],'mTp',[],...
                  'mb',[],'mbc',[],'mTpacc',[]);

function ExecSkedRegulators()
         global SkedData;
         // External PI (round duration)
         SkedData.eTr   = SkedData.SP_Tr-SkedData.Tr;

         bc             = SkedData.bco+SkedData.krr*SkedData.eTr...
                          -SkedData.krr*SkedData.zrr*SkedData.eTro;
         if sum(SkedData.saturated)<>0 then
             SkedData.bc=bc;
         else
             if bc<SkedData.bc then
                 SkedData.bc=bc;
             end
         end
         
         SkedData.bco   = SkedData.bc;
         
         SkedData.eTro  = SkedData.eTr;
         SkedData.SP_Tp = SkedData.alfa*(SkedData.bc+SkedData.Tr);
         // Internal I with AW (CPU usage within round)
         SkedData.eTp   = SkedData.SP_Tp-SkedData.Tp;
         
         // Feedforward
         b              = SkedData.bo+SkedData.kpi.*SkedData.eTp;
         b              = min(max(b,SkedData.bmin),SkedData.bmax);
         SkedData.b     = SkedData.alfaBlock.*SkedData.b+...
                          (ones(SkedData.alfaBlock)-SkedData.alfaBlock).*b;
         // Reinit
         justAwaken     = (~SkedData.alfaBlock) & SkedData.alfaBlocko;
         for i=1:length(SkedData.b) //awaken is an array of bool
             if justAwaken(i) then
                 SkedData.b(i)=SkedData.alfa(i)*SkedData.SP_Tr;
                 if SkedData.b(i)>SkedData.bmax then
                     printf("Warning: burst greater than bmax\n");
                 end
                 if SkedData.b(i)<SkedData.bmin then
                     printf("Warning: burst lower than bmin\n");
                 end
             end
         end
         SkedData.saturated=SkedData.bmax-SkedData.b;
         SkedData.bo    = SkedData.b;
         SkedData.alfaBlocko = SkedData.alfaBlock;
endfunction

function ExecProcPool()
         global SkedData;
         
         roundIndex=[]; //List of task indexes composing the round
         tasks=length(SkedData.b);
         for i=1:tasks
             SkedData.Tp(i)=0; //Reset all processing times
             if SkedData.alfaBlock(i)==0 then
                 roundIndex=[roundIndex,i];
                 SkedData.bRemaining(i)=SkedData.b(i);
             else
                 //Assign nominal burst to blocked tasks, in case they wake up
                 SkedData.bRemaining(i)=SkedData.alfa(i)*SkedData.SP_Tr;
                 if SkedData.bRemaining(i)>SkedData.bmax then
                     printf("Warning: remaining burst greater than bmax\n");
                 end
                 if SkedData.bRemaining(i)<SkedData.bmin then
                     printf("Warning: remaining burst lower than bmin\n");
                 end
             end
         end
         
         cur=1; //Index of currently running task
         tStart=0; //Time from round start
//         printf("---\n");
         while cur<=length(roundIndex)
             idx=roundIndex(cur);
//             disp([SkedData.bRemaining(idx),SkedData.cpuRemaining(idx)]);
             //Tentative burst considering cpuRemaining
             b=min(SkedData.bRemaining(idx),SkedData.cpuRemaining(idx));
             
             if b<SkedData.bmin then
                 continue
             end
             
             //Compute the closest wakeup time
             wakeups=SkedData.sleepPoint+SkedData.Toff;
             firstWakeups=find(wakeups==min(wakeups));
             firstWakeup=firstWakeups(1);
             firstWakeupTime=SkedData.sleepPoint(firstWakeup)...
                 +SkedData.Toff(firstWakeup);
             
             //Check if that wakeup happens inside the current burst
             if firstWakeupTime<SkedData.t+tStart+b ...
              & SkedData.bRemaining(firstWakeup)>0 then
                b=firstWakeupTime-SkedData.t-tStart;
                //Note: cur is repeated twice as its burst is not completed
                roundIndex=[roundIndex(1:cur),firstWakeup,roundIndex(cur:$)];
                
                SkedData.alfaBlock(firstWakeup)=0;
                SkedData.sleepPoint(firstWakeup)=1e10;
                SkedData.cpuRemaining(firstWakeup)=SkedData.Ton(firstWakeup);
             end
             
             //Now that b is the real burst, check whether we need to sleep
             SkedData.cpuRemaining(idx)=SkedData.cpuRemaining(idx)-b;
             SkedData.bRemaining(idx)=SkedData.bRemaining(idx)-b;
             if SkedData.bRemaining(idx)<0 then
                 printf("Error: negative burst remaining\n");
             end
             if SkedData.cpuRemaining(idx)<0 then
                 printf("Error: negative cpu remaining\n");
             end
             if SkedData.cpuRemaining(idx)==0 then
                 SkedData.alfaBlock(idx)=1;
                 SkedData.sleepPoint(idx)=SkedData.t+tStart+b;
                 SkedData.cpuRemaining(firstWakeup)=1e10;
             end
             
             SkedData.Tp(idx)=SkedData.Tp(idx)+b;
             SkedData.Tpacc(idx)=SkedData.Tpacc(idx)+b;
             tStart=tStart+b;
             cur=cur+1;
//             disp([SkedData.bRemaining(idx),SkedData.cpuRemaining(idx)]);
//             disp(roundIndex);
//             xclick();
         end
         SkedData.Tr = sum(SkedData.Tp);
         SkedData.t  = SkedData.t+SkedData.Tr;
endfunction

function AddBatchTask()
    global SkedData;
    idx=length(SkedData.b)+1;
    SkedData.alfaBlock    = [SkedData.alfaBlock,0];
    SkedData.alfaBlocko   = [SkedData.alfaBlocko,0];
    SkedData.SP_Tp        = [SkedData.SP_Tp,SkedData.alfa(idx)*SkedData.SP_Tr];
    SkedData.eTp          = [SkedData.eTp,0];
    SkedData.b            = [SkedData.b,SkedData.SP_Tp(idx)];
    SkedData.bo           = [SkedData.bo,SkedData.SP_Tp(idx)];
    SkedData.Tp           = [SkedData.Tp,SkedData.SP_Tp(idx)];
    SkedData.Tpacc        = [SkedData.Tpacc,0];
    SkedData.Ton          = [SkedData.Ton,0];
    SkedData.Toff         = [SkedData.Toff,0];
    SkedData.sleepPoint   = [SkedData.sleepPoint,1e10];
    SkedData.bRemaining   = [SkedData.bRemaining,0];
    SkedData.cpuRemaining = [SkedData.cpuRemaining,1e10];
    SkedData.saturated    = [SkedData.saturated,0];
endfunction

function AddPeriodicTask(Ton,Toff)
    global SkedData;
    idx=length(SkedData.b)+1;
    SkedData.alfaBlock    = [SkedData.alfaBlock,0];
    SkedData.alfaBlocko   = [SkedData.alfaBlocko,0];
    SkedData.SP_Tp        = [SkedData.SP_Tp,SkedData.alfa(idx)*SkedData.SP_Tr];
    SkedData.eTp          = [SkedData.eTp,0];
    SkedData.b            = [SkedData.b,SkedData.SP_Tp(idx)];
    SkedData.bo           = [SkedData.bo,SkedData.SP_Tp(idx)];
    SkedData.Tp           = [SkedData.Tp,SkedData.SP_Tp(idx)];
    SkedData.Tpacc        = [SkedData.Tpacc,0];
    SkedData.Ton          = [SkedData.Ton,Ton];
    SkedData.Toff         = [SkedData.Toff,Toff];
    SkedData.sleepPoint   = [SkedData.sleepPoint,1e10];
    SkedData.bRemaining   = [SkedData.bRemaining,0];
    SkedData.cpuRemaining = [SkedData.cpuRemaining,Ton];
    SkedData.saturated    = [SkedData.saturated,0];
endfunction

function GetSimRes()
        global SkedData;
        global SimRes;
        SimRes.mt     = [SimRes.mt,SkedData.t];
        SimRes.mSP_Tr = [SimRes.mSP_Tr,SkedData.SP_Tr];
        SimRes.mTr    = [SimRes.mTr,SkedData.Tr];
        SimRes.mbc    = [SimRes.mbc,SkedData.bc];
        
        vSP_Tp        = SkedData.alfa*(SkedData.Tr+SkedData.bc);
        SimRes.mSP_Tp = [SimRes.mSP_Tp,vSP_Tp'];
        SimRes.mTp    = [SimRes.mTp,SkedData.Tp'];
        SimRes.mb     = [SimRes.mb,SkedData.b'];
        SimRes.mTpacc = [SimRes.mTpacc,SkedData.Tpacc'];
endfunction

//--------------------------------------------

// Controller parameters
SkedData.kpi     = 0.25;
SkedData.krr     = 1.4;
SkedData.zrr     = 0.88;
SkedData.bmin    = 0;
SkedData.bmax    = 15;

// Simulation duration
Nrounds          = 200;

//Simulation data
SkedData.SP_Tr   = 10;
//SkedData.alfa    = [0.3 0.2 0.5];
//AddBatchTask();
//AddBatchTask();
//AddPeriodicTask(15,10);
SkedData.alfa    = [0.1 0.9];
AddBatchTask();
AddPeriodicTask(1,1);

if sum(SkedData.alfa)<>1 then
    printf("Error: alfa do not sum to one\n");
end
SkedData.Tr      = SkedData.SP_Tr;
for i=1:Nrounds
    ExecSkedRegulators();
    ExecProcPool();
    GetSimRes();
    
    if i==150 then
        SkedData.alfaBlock(2)=0;
        SkedData.Ton(2)=0;
        SkedData.Toff(2)=0;
        SkedData.sleepPoint(2)=1e10;
        SkedData.cpuRemaining(2)=1e10;
    end
    
end

hf=scf(0); clf;
hf.figure_size = [1100,700];
drawlater();
subplot(311);
   plot([1:1:Nrounds],SimRes.mSP_Tr,'r');
   plot([1:1:Nrounds],SimRes.mTr,'k');
   plot([1:1:Nrounds],SimRes.mbc,'g');   
   title('Round duration (black) set point (red) and burst correction (green)');
   ax = get("current_axes");
   ax.tight_limits = "on";
subplot(312);
   plot([1:1:Nrounds],SimRes.mSP_Tp,'r');
   plot([1:1:Nrounds],SimRes.mTp,'k');
   title('Processes CPU use (black) vs set point (red)');
   ax = get("current_axes");
   ax.tight_limits = "on";
subplot(313);
   plot([1:1:Nrounds],SimRes.mTpacc);
drawnow();
