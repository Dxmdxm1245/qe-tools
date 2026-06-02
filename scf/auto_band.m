%% =========================================================
%  Electron band: read .gnu -> process -> plot -> save
%% =========================================================
clear; clc; close all;

%% =========================
% 1. 用户参数
%% =========================
INPUT_FILE = 'D:\works\实验\26.4\epw\diam-dft.gnu';

% ===== 能量平移 =====
% 如果你想以费米能或 VBM 为 0，就把对应数值填到这里
% 最终画图时用：E_plot = E_raw - ENERGY_SHIFT
ENERGY_SHIFT = 0.0;

% ===== 横坐标归一化开关 =====
% true  -> k 和 K_NODES 都归一化到 [0,1]
% false -> 保持原始横坐标
NORMALIZE_K = true;

% ===== 图像设置 =====
Y_LABEL = 'Energy (eV)';
TITLE_STR = '';   % 不要标题就留空
YLIM_RANGE = [];  % 例如 [-10 12]

% ===== 高对称点位置与标签 =====
% 自己按路径填；不填就只画普通横坐标
% 例：
% K_NODES  = [0 0.6179 1.1763 1.7633 2.3812 3.5612 3.8702];
% K_LABELS = {'\Gamma','X','P','N','\Gamma','M','S'};
K_NODES  = [0, 1.6380, 1.9872];
K_LABELS = {'\Gamma','X','U'};

% 是否导出 CSV
WRITE_CSV = true;

% ===== 样式 =====
FIG_W = 900;
FIG_H = 650;
LW_BAND = 1.8;
LW_AXIS = 1.8;
LW_VLINE = 1.2;
FS_AXIS = 18;
FS_TICK = 16;
FONT_NAME = 'Arial';

DRAW_ZERO_LINE = true;   % 画 y = 0 参考线

%% =========================
% 2. 自动生成输出文件名
%% =========================
[inFolder, inName, inExt] = fileparts(INPUT_FILE);

if isempty(inExt)
    INPUT_FILE_REAL = INPUT_FILE;
else
    INPUT_FILE_REAL = fullfile(inFolder, [inName inExt]);
end

OUT_CSV = fullfile(inFolder, [inName '.csv']);
OUT_PNG = fullfile(inFolder, [inName '.png']);
OUT_FIG = fullfile(inFolder, [inName '.fig']);

%% =========================
% 3. 读取并整理数据
%% =========================
[k, bands_raw] = load_electron_bands(INPUT_FILE_REAL);

% 能量平移
bands = bands_raw - ENERGY_SHIFT;

% ===== 横坐标归一化 =====
K_NODES_plot = K_NODES;   % 复制一份用于绘图/导出
if NORMALIZE_K
    kmax = max(k);
    if kmax > 0
        k = k ./ kmax;
        if ~isempty(K_NODES_plot)
            K_NODES_plot = K_NODES_plot ./ kmax;
        end
    else
        warning('k 的最大值 <= 0，无法归一化，保持原始横坐标。');
    end
end

% 保存宽表：第一列 k，后面每列是一条 band
if WRITE_CSV
    outMat = [k, bands];
    header = cell(1, size(outMat,2));
    if NORMALIZE_K
        header{1} = 'k_normalized';
    else
        header{1} = 'k';
    end
    for ib = 1:size(bands,2)
        header{ib+1} = sprintf('band_%d', ib);
    end

    writecell(header, OUT_CSV);
    writematrix(outMat, OUT_CSV, 'WriteMode', 'append');
    fprintf('处理后的宽表已保存：%s\n', OUT_CSV);
end

%% =========================
% 4. 直接绘图
%% =========================
fig = figure('Color', 'w', 'Position', [100, 100, FIG_W, FIG_H]);
hold on;

nb = size(bands, 2);
for ib = 1:nb
    plot(k, bands(:, ib), 'k-', 'LineWidth', LW_BAND);
end

% 高对称点竖线
if ~isempty(K_NODES_plot)
    for i = 1:numel(K_NODES_plot)
        xline(K_NODES_plot(i), '-', 'LineWidth', LW_VLINE, 'Color', [0.5 0.5 0.5]);
    end
end

% y = 0 参考线
if DRAW_ZERO_LINE
    yline(0, '--', 'LineWidth', 1.0, 'Color', [0.4 0.4 0.4]);
end

xlim([min(k), max(k)]);
if ~isempty(YLIM_RANGE)
    ylim(YLIM_RANGE);
end

ylabel(Y_LABEL, 'FontName', FONT_NAME, 'FontSize', FS_AXIS, 'FontWeight', 'bold');
if ~isempty(TITLE_STR)
    title(TITLE_STR, 'FontName', FONT_NAME, 'FontSize', FS_AXIS, 'FontWeight', 'bold');
end

if ~isempty(K_NODES_plot) && ~isempty(K_LABELS)
    xticks(K_NODES_plot);
    xticklabels(K_LABELS);
end

ax = gca;
ax.FontName = FONT_NAME;
ax.FontSize = FS_TICK;
ax.LineWidth = LW_AXIS;
ax.Box = 'on';
ax.TickDir = 'in';
ax.TickLength = [0.015 0.015];

if NORMALIZE_K
    xlabel('Normalized k path', 'FontName', FONT_NAME, 'FontSize', FS_AXIS, 'FontWeight', 'bold');
else
    xlabel('');
end

hold off;

%% =========================
% 5. 保存图片
%% =========================
exportgraphics(fig, OUT_PNG, 'Resolution', 600);
savefig(fig, OUT_FIG);

fprintf('图已保存：%s\n', OUT_PNG);
fprintf('MATLAB 图文件已保存：%s\n', OUT_FIG);

%% =========================================================
% 6. 本地函数
%% =========================================================
function [k, bands] = load_electron_bands(filename)
    % 支持：
    % 1) QE .gnu 两列格式，每条 band 之间有空行
    % 2) 两列格式，靠 k 回跳分段
    % 3) 已经是宽表：第一列 k，后面每列 band

    raw = readmatrix(filename, 'FileType', 'text');

    if isempty(raw)
        error('文件为空或读取失败：%s', filename);
    end

    % 去掉全空列
    raw(:, all(isnan(raw), 1)) = [];

    if size(raw, 2) < 2
        error('数据列数不足，至少需要 2 列。');
    end

    % ---------- 情况 A：已经是宽表 ----------
    if size(raw, 2) > 2
        data = raw(~all(isnan(raw), 2), :);
        k = data(:, 1);
        bands = data(:, 2:end);
        bands(:, all(isnan(bands), 1)) = [];
        return;
    end

    % ---------- 情况 B：两列 + 空行分块 ----------
    sepRow = all(isnan(raw), 2);

    blocks = {};
    startRow = 1;
    nrow = size(raw, 1);

    for i = 1:(nrow + 1)
        if i == nrow + 1 || sepRow(i)
            chunk = raw(startRow:i-1, 1:2);
            chunk = chunk(all(~isnan(chunk), 2), :);
            if ~isempty(chunk)
                blocks{end+1} = chunk; %#ok<AGROW>
            end
            startRow = i + 1;
        end
    end

    % ---------- 如果没有空行分块，就按 k 回跳分段 ----------
    if isempty(blocks) || numel(blocks) == 1
        data = raw(:, 1:2);
        data = data(all(~isnan(data), 2), :);

        x = data(:, 1);
        y = data(:, 2);

        cutIdx = find(diff(x) < -1e-12 | (x(2:end) == 0 & x(1:end-1) ~= 0));

        idx = [1; cutIdx + 1; numel(x) + 1];
        blocks = cell(1, numel(idx) - 1);
        for j = 1:numel(idx)-1
            blocks{j} = [x(idx(j):idx(j+1)-1), y(idx(j):idx(j+1)-1)];
        end
    end

    if isempty(blocks)
        error('未识别到任何 band。');
    end

    % ---------- 组装成宽表 ----------
    nBands = numel(blocks);
    k = blocks{1}(:, 1);
    nPts = numel(k);

    bands = nan(nPts, nBands);

    for ib = 1:nBands
        blk = blocks{ib};

        if size(blk, 1) ~= nPts
            error('第 %d 条 band 的点数与第一条不一致。', ib);
        end

        if max(abs(blk(:, 1) - k)) > 1e-8
            error('第 %d 条 band 的 k 网格与第一条不一致。', ib);
        end

        bands(:, ib) = blk(:, 2);
    end
end