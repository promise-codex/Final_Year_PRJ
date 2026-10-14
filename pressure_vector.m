% Pressure vector model: 4-20 mA transducer -> 250 ohm shunt -> 10-bit ADC.
% Plots the signal-chain linearity, the digital threshold against the analog
% relay hysteresis band, and the ADC quantisation error.

clear; clc; close all;

I_min    = 4e-3;
I_max    = 20e-3;
R_sense  = 250;
V_ref    = 5.0;
N_bits   = 10;
N_levels = 2^N_bits;

PR_THRESHOLD_PCT = 5;    % treat pressure above this (% of full scale) as rising

P = linspace(0, 100, 1001);

I_loop  = I_min + (I_max - I_min) .* (P ./ 100);
V_sense = I_loop .* R_sense;                    % Ohm's law
ADC_ideal = (V_sense ./ V_ref) .* N_levels;
ADC_code  = min(floor(ADC_ideal), N_levels - 1);

ADC_baseline = floor((I_min*R_sense / V_ref) * N_levels);   % 204 at 4 mA
ADC_full     = floor((I_max*R_sense / V_ref) * N_levels);   % 1023 at 20 mA

V_thr   = (I_min + (I_max - I_min)*(PR_THRESHOLD_PCT/100)) * R_sense;
ADC_thr = floor((V_thr / V_ref) * N_levels);

fprintf('0%%   : 4 mA  -> %.2f V -> code %d\n', I_min*R_sense, ADC_baseline);
fprintf('100%% : 20 mA -> %.2f V -> code %d\n', I_max*R_sense, ADC_full);
fprintf('thr  : %.2f mA -> %.3f V -> code %d\n\n', 1e3*(V_thr/R_sense), V_thr, ADC_thr);

% representative relay dead band around the nominal threshold
HYST_HALF_WIDTH_PCT = 6;
P_engage  = PR_THRESHOLD_PCT + HYST_HALF_WIDTH_PCT;
P_release = max(PR_THRESHOLD_PCT - HYST_HALF_WIDTH_PCT, 0);

% --- signal chain linearity (voltage + ADC code on twin axes) ---
f1 = figure('Name','Signal Chain Linearity','Color','w','Position',[100 100 760 520]);
yyaxis left
plot(P, V_sense, 'LineWidth', 2);
ylabel('Sense voltage across R_{sense}  (V)'); ylim([0 5.2]);
ax = gca; ax.YColor = [0 0.45 0.74];
yyaxis right
plot(P, ADC_code, 'LineWidth', 2);
ylabel('ADC code  (0 - 1023)'); ylim([0 1060]);
ax.YColor = [0.85 0.33 0.10];
xlabel('Applied pressure  (% of full scale)');
title('Pressure Vector: 4-20 mA \rightarrow Voltage \rightarrow ADC Code');
grid on; box on;
yyaxis right; hold on;
plot(0, ADC_baseline, 'ko', 'MarkerFaceColor','k');
plot(100, ADC_full, 'ko', 'MarkerFaceColor','k');
text(3, ADC_baseline+55, sprintf('4 mA \\rightarrow code %d', ADC_baseline));
text(100, ADC_full-55, sprintf('20 mA \\rightarrow code %d', ADC_full), ...
     'HorizontalAlignment','right');

% --- digital threshold vs analog hysteresis ---
f2 = figure('Name','Digital vs Analog Switching','Color','w','Position',[120 120 760 520]);
hold on; box on; grid on;
yl = [0 1];
patch([P_release P_engage P_engage P_release], [yl(1) yl(1) yl(2) yl(2)], ...
      [1 0.85 0.85], 'EdgeColor','none');
Pr_digital = double(ADC_code >= ADC_thr);
plot(P, Pr_digital, 'LineWidth', 2.5, 'Color',[0 0.45 0.74]);
plot([P_engage P_engage], yl, '--', 'Color',[0.75 0 0], 'LineWidth',1.3);
plot([P_release P_release], yl, '--', 'Color',[0.75 0 0], 'LineWidth',1.3);
plot([PR_THRESHOLD_PCT PR_THRESHOLD_PCT], yl, ':', 'Color',[0 0.3 0.6], 'LineWidth',1.3);
ylim([-0.1 1.2]); xlim([0 30]);
yticks([0 1]); yticklabels({'Pr = 0 (idle)','Pr = 1 (pressurising)'});
xlabel('Applied pressure  (% of full scale)');
title('Deterministic Digital Threshold vs. Analog Relay Hysteresis');
text(mean([P_release P_engage]), 0.5, {'Analog relay','dead band','(undefined state)'}, ...
     'HorizontalAlignment','center','FontSize',9,'Color',[0.6 0 0]);
text(PR_THRESHOLD_PCT+0.5, 1.12, 'single digital switching point', ...
     'FontSize',9,'Color',[0 0.3 0.6]);
legend({'Analog hysteresis band','Digital decision Pr','Relay engage edge', ...
        'Relay release edge','Digital threshold'}, 'Location','southeast','FontSize',8);

% --- ADC quantisation error ---
f3 = figure('Name','ADC Quantisation Error','Color','w','Position',[140 140 760 420]);
q_err = ADC_ideal - ADC_code;
plot(P, q_err, 'LineWidth', 1.2, 'Color',[0.2 0.2 0.2]);
ylim([-0.1 1.1]); grid on; box on;
xlabel('Applied pressure  (% of full scale)');
ylabel('Quantisation error  (LSB)');
title('10-bit ADC Quantisation Error (bounded below 1 LSB)');
yline(1,'--','1 LSB ceiling');

print(f1, 'fig_pressure_linearity',   '-dpng','-r200');
print(f2, 'fig_digital_vs_hysteresis','-dpng','-r200');
print(f3, 'fig_quantisation_error',   '-dpng','-r200');
fprintf('Saved 3 figures.\n');
