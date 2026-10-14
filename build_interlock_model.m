% Builds the Simulink/Stateflow model of the interlock logic and runs a
% test scenario. Logic: M = ~H, P = M & ~H & Pr, entry on A & (Pr==0),
% auto-latch 3 s after the bay goes clear.

function build_interlock_model()

    modelName = 'SafetyInterlock';
    CLEAR_SECS = 3;

    close_system(modelName, 0);     %#ok<*TRYNC>
    if exist([modelName '.slx'],'file'); delete([modelName '.slx']); end

    new_system(modelName);
    open_system(modelName);

    % inputs as From Workspace blocks (timeseries built below)
    add_block('simulink/Sources/From Workspace', [modelName '/A'],  ...
        'VariableName','A_ts',  'Position',[30  40  90  70]);
    add_block('simulink/Sources/From Workspace', [modelName '/H'],  ...
        'VariableName','H_ts',  'Position',[30 110  90 140]);
    add_block('simulink/Sources/From Workspace', [modelName '/Pr'], ...
        'VariableName','Pr_ts', 'Position',[30 180  90 210]);

    % chart via the Stateflow API so we get the handle directly
    mdlHandle = get_param(modelName,'Handle');
    chart = Stateflow.Chart(mdlHandle);
    chart.Name     = 'InterlockLogic';
    chart.Position = [180 60 380 220];
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
        '  P = (Pr == 1) && (H == 0);']);

    sUnlocked = Stateflow.State(chart);
    sUnlocked.Name = 'UNLOCKED';
    sUnlocked.Position = [40 200 150 90];
    sUnlocked.LabelString = sprintf([ ...
        'UNLOCKED\n' ...
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

    % bay clear for 3 s -> latch again
    t2 = Stateflow.Transition(chart);
    t2.Source = sUnlocked;
    t2.Destination = sLatched;
    t2.LabelString = sprintf('after(%d,sec) [H == 0]', CLEAR_SECS);
    t2.SourceOClock = 12;
    t2.DestinationOClock = 6;

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
    sim(modelName);
    fprintf('Done. Open the Scope for M and P.\n');

end

function makeData(chart, name, scope)
    d = Stateflow.Data(chart);
    d.Name     = name;
    d.Scope    = scope;
    d.DataType = 'double';
end
