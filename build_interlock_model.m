% Builds the Simulink/Stateflow model of the interlock logic and runs a
% test scenario. It mirrors PressureRoomLock_CV.ino:
%   LATCHED  -> UNLOCKED  on a valid card with zero pressure (A & Pr==0)
%   UNLOCKED -> CLEARING  when the bay reads clear (H==0)
%   CLEARING -> UNLOCKED  if a person is seen again (H==1), timer restarts
%   CLEARING -> LATCHED   after the bay has stayed clear for 3 s
% Outputs: M = 1 only in LATCHED, P = M & ~H & Pr.
% v1.1: the clear timer now starts when the bay goes clear, not when the
% door unlocks (v1.0 used after(3,sec)[H==0] on UNLOCKED, which latched
% as soon as H fell if the door had been open for 3 s or more).

function build_interlock_model()

    modelName = 'SafetyInterlock';
    CLEAR_SECS = 3;

    close_system(modelName, 0);     %#ok<*TRYNC>
    if exist([modelName '.slx'],'file'); delete([modelName '.slx']); end

    new_system(modelName);
    open_system(modelName);

    % inputs as From Workspace blocks (timeseries built below)
    add_block('simulink/Sources/From Workspace', [modelName '/A'],  ...
        'VariableName','A_ts', 'Interpolate','off', 'OutputAfterFinalValue','Holding final value',  'Position',[30  40  90  70]);
    add_block('simulink/Sources/From Workspace', [modelName '/H'],  ...
        'VariableName','H_ts', 'Interpolate','off', 'OutputAfterFinalValue','Holding final value',  'Position',[30 110  90 140]);
    add_block('simulink/Sources/From Workspace', [modelName '/Pr'], ...
        'VariableName','Pr_ts', 'Interpolate','off', 'OutputAfterFinalValue','Holding final value', 'Position',[30 180  90 210]);

    % chart block from the Stateflow library, then its API handle
    load_system('sflib');
    add_block('sflib/Chart', [modelName '/InterlockLogic'], 'Position',[180 60 380 220]);
    chart = find(sfroot, '-isa','Stateflow.Chart', 'Path',[modelName '/InterlockLogic']);
    assert(~isempty(chart) && isvalid(chart), ...
        'Could not create the Stateflow chart in %s.', modelName);

    % ports, created in order so A,H,Pr -> 1,2,3 in and M,P -> 1,2 out
    makeData(chart,'A','Input');
    makeData(chart,'H','Input');
    makeData(chart,'Pr','Input');
    makeData(chart,'M','Output');
    makeData(chart,'P','Output');

    sLatched = Stateflow.State(chart);
    sLatched.Name = 'LATCHED';
    sLatched.Position = [40 40 150 90];
    sLatched.LabelString = sprintf([ ...
        'LATCHED\n' ...
        'en,du:\n' ...
        '  M = 1;\n' ...
        '  P = Pr * (1 - H);']);

    sUnlocked = Stateflow.State(chart);
    sUnlocked.Name = 'UNLOCKED';
    sUnlocked.Position = [40 200 150 90];
    sUnlocked.LabelString = sprintf([ ...
        'UNLOCKED\n' ...
        'en,du:\n' ...
        '  M = 0;\n' ...
        '  P = 0;']);

    sClearing = Stateflow.State(chart);
    sClearing.Name = 'CLEARING';
    sClearing.Position = [260 200 150 90];
    sClearing.LabelString = sprintf([ ...
        'CLEARING\n' ...
        'en,du:\n' ...
        '  M = 0;\n' ...
        '  P = 0;']);

    % start in LATCHED
    dflt = Stateflow.Transition(chart);
    dflt.Destination = sLatched;
    dflt.DestinationOClock = 0;
    dflt.SourceEndpoint = [sLatched.Position(1)+60, sLatched.Position(2)-30];
    dflt.MidPoint       = [sLatched.Position(1)+60, sLatched.Position(2)-15];

    % valid card + no pressure -> unlock
    t1 = Stateflow.Transition(chart);
    t1.Source = sLatched;
    t1.Destination = sUnlocked;
    t1.LabelString = '[A == 1 && Pr == 0]';
    t1.SourceOClock = 6;
    t1.DestinationOClock = 12;

    % bay reads clear -> start the clear timer
    t2 = Stateflow.Transition(chart);
    t2.Source = sUnlocked;
    t2.Destination = sClearing;
    t2.LabelString = '[H == 0]';
    t2.SourceOClock = 3;
    t2.DestinationOClock = 9;

    % person seen again -> back to UNLOCKED (timer restarts)
    t3 = Stateflow.Transition(chart);
    t3.Source = sClearing;
    t3.Destination = sUnlocked;
    t3.LabelString = '[H == 1]';
    t3.SourceOClock = 8;
    t3.DestinationOClock = 4;

    % clear for CLEAR_SECS -> latch
    t4 = Stateflow.Transition(chart);
    t4.Source = sClearing;
    t4.Destination = sLatched;
    t4.LabelString = sprintf('after(%d,sec)', CLEAR_SECS);
    t4.SourceOClock = 12;
    t4.DestinationOClock = 3;

    add_block('simulink/Sinks/Scope', [modelName '/Scope'], ...
        'Position',[460 90 510 190]);
    add_block('simulink/Signal Routing/Mux', [modelName '/Mux'], ...
        'Inputs','2','Position',[410 100 415 180]);

    add_line(modelName,'A/1','InterlockLogic/1','autorouting','on');
    add_line(modelName,'H/1','InterlockLogic/2','autorouting','on');
    add_line(modelName,'Pr/1','InterlockLogic/3','autorouting','on');
    add_line(modelName,'InterlockLogic/1','Mux/1','autorouting','on');
    add_line(modelName,'InterlockLogic/2','Mux/2','autorouting','on');
    add_line(modelName,'Mux/1','Scope/1','autorouting','on');

    % root outports so the run returns M and P for checking
    add_block('simulink/Sinks/Out1', [modelName '/Mout'], 'Position',[460 230 490 244]);
    add_block('simulink/Sinks/Out1', [modelName '/Pout'], 'Position',[460 270 490 284]);
    add_line(modelName,'InterlockLogic/1','Mout/1','autorouting','on');
    add_line(modelName,'InterlockLogic/2','Pout/1','autorouting','on');

    p = get_param([modelName '/InterlockLogic'],'PortHandles');
    set_param(p.Outport(1),'Name','M');
    set_param(p.Outport(2),'Name','P');

    set_param(modelName,'SolverType','Fixed-step','Solver','FixedStepDiscrete', ...
        'FixedStep','0.05','StopTime','20');

    % scenario: idle, pressure up at 2, person in at 5 (interrupts P),
    % card at 7 with pressure off (entry), person stays to 12, leaves,
    % auto-latch at 15, pressure up again at 16.
    t = (0:0.05:20)';
    A  = zeros(size(t));
    H  = zeros(size(t));
    Pr = zeros(size(t));

    Pr(t>=2 & t<5)   = 1;
    H(t>=5 & t<7)    = 1;
    Pr(t>=5 & t<7)   = 1;
    Pr(t>=7)         = 0;
    A(abs(t-7)<0.03) = 1;
    H(t>=7 & t<12)   = 1;
    Pr(t>=16)        = 1;

    A_ts  = timeseries(A,  t);
    H_ts  = timeseries(H,  t);
    Pr_ts = timeseries(Pr, t);
    assignin('base','A_ts',A_ts);
    assignin('base','H_ts',H_ts);
    assignin('base','Pr_ts',Pr_ts);

    save_system(modelName);
    fprintf('Built %s, simulating...\n', modelName);
    out = sim(modelName, 'SaveOutput','on', 'OutputSaveName','yout', 'SaveFormat','Dataset');
    fprintf('Done. Open the Scope for M and P.\n');

    % print the switching times so they can be checked against the paper
    % (expected: M falls at 7.00 s and rises at 15.00 s;
    %            P rises at 2.00 s, falls at 5.00 s, rises at 16.00 s)
    try
        ys = out.yout;
        tM = ys{1}.Values.Time; M = ys{1}.Values.Data;
        tP = ys{2}.Values.Time; P = ys{2}.Values.Data;
        fprintf('M edges (s): %s\n', mat2str(tM(find(diff(M))+1)', 4));
        fprintf('P edges (s): %s\n', mat2str(tP(find(diff(P))+1)', 4));
    catch
        fprintf('Read the edges from the Scope: M down 7 s, up 15 s; P up 2 s, down 5 s, up 16 s.\n');
    end

end

function makeData(chart, name, scope)
    d = Stateflow.Data(chart);
    d.Name     = name;
    d.Scope    = scope;
    d.DataType = 'double';
end
