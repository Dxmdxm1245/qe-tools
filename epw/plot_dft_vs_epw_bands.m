function plot_dft_epw_bands_from_eig()
    clc; close all;

    %% ================= 用户参数 =================
    dftFile = 'D:\works\实验\26.4\epw\diam-dft.gnu';
    epwEigFile = 'D:\works\实验\26.4\epw\band.eig';

    % 参考能量，例如 VBM / Fermi level
    Eref = 15.52785;   % eV

    % 纵轴范围
    yl = [-2, 15];

    % 高对称点标签
    xLabels = {'\Gamma','X','U'};

    % DFT 高对称点原始横坐标
    dftTicks = [0, 1.6380, 1.9872];

    % EPW 节点索引，强烈推荐手动指定
    % 例如 Γ-X-U，总共 81 个点，X 在 41：
    epwTurnIdx = [1, 100, 199];

    % 如果你不想手动指定，可设为空 []，程序会尝试自动识别转折点
    % epwTurnIdx = [];

    % 分段归一化后的横坐标
    xTicks_new = [0, 1, 2];

    %% ================= 晶格参数：用于从 band.eig 的 k 点构造 QE 风格横坐标 =================
    % 这里填你的 CELL_PARAMETERS(alat) 里的无量纲晶格矢量
    Afrac = [
       -0.506207309   0.000000000   0.506207309;
        0.000000000   0.506207309   0.506207309;
       -0.506207309   0.506207309   0.000000000
    ];

    % 不乘 2*pi，不乘 alat；用于构造与 QE .gnu 类似的路径长度
    Bqe = inv(Afrac)';

    %% ================= 读取 DFT band =================
    dftBands = read_band_file_blanksep(dftFile);
    if isempty(dftBands)
        error('DFT band 文件为空或读取失败。');
    end

    x_dft = dftBands{1}(:,1);

    idxG_dft = find_closest_idx(x_dft, dftTicks(1));
    idxX_dft = find_closest_idx(x_dft, dftTicks(2));
    idxU_dft = find_closest_idx(x_dft, dftTicks(3));

    check_turn_idx([idxG_dft, idxX_dft, idxU_dft], 'DFT');

    fprintf('DFT 节点索引: Γ=%d, X=%d, U=%d\n', idxG_dft, idxX_dft, idxU_dft);
    fprintf('DFT 节点原始 x: Γ=%.6f, X=%.6f, U=%.6f\n', ...
        x_dft(idxG_dft), x_dft(idxX_dft), x_dft(idxU_dft));

    %% ================= 读取 EPW band.eig =================
    [kvec_epw, E_epw] = read_epw_band_eig(epwEigFile);

    nks = size(E_epw, 1);
    nbnd = size(E_epw, 2);

    % 由 k 点构造 EPW 横坐标
    x_epw = zeros(nks, 1);
    for ik = 2:nks
        dk_frac = kvec_epw(ik,:) - kvec_epw(ik-1,:);
        dk_qe = dk_frac * Bqe;
        x_epw(ik) = x_epw(ik-1) + norm(dk_qe);
    end

    % 找 EPW Γ-X-U 节点
    if isempty(epwTurnIdx)
        epwTurnIdx = detect_turning_points(kvec_epw);
    end

    if numel(epwTurnIdx) ~= 3
        error('当前脚本要求 Γ-X-U 三个节点。检测到 %d 个节点，请手动设置 epwTurnIdx = [idxG, idxX, idxU]。', ...
            numel(epwTurnIdx));
    end

    idxG_epw = epwTurnIdx(1);
    idxX_epw = epwTurnIdx(2);
    idxU_epw = epwTurnIdx(3);

    check_turn_idx([idxG_epw, idxX_epw, idxU_epw], 'EPW');

    fprintf('EPW 节点索引: Γ=%d, X=%d, U=%d\n', idxG_epw, idxX_epw, idxU_epw);
    fprintf('EPW 节点原始 x: Γ=%.6f, X=%.6f, U=%.6f\n', ...
        x_epw(idxG_epw), x_epw(idxX_epw), x_epw(idxU_epw));

    %% ================= 作图 =================
    figure('Color', 'w', 'Position', [100, 100, 900, 650]);
    hold on; box on;

    %% ---------- DFT: Γ-X ----------
    for ib = 1:numel(dftBands)
        xd = dftBands{ib}(idxG_dft:idxX_dft, 1);
        yd = dftBands{ib}(idxG_dft:idxX_dft, 2) - Eref;

        xd_map = map_to_interval(xd, xd(1), xd(end), 0, 1);

        if ib == 1
            plot(xd_map, yd, 'b--', 'LineWidth', 1.2, 'DisplayName', 'DFT');
        else
            plot(xd_map, yd, 'b--', 'LineWidth', 1.2, 'HandleVisibility', 'off');
        end
    end

    %% ---------- DFT: X-U ----------
    for ib = 1:numel(dftBands)
        xd = dftBands{ib}(idxX_dft:idxU_dft, 1);
        yd = dftBands{ib}(idxX_dft:idxU_dft, 2) - Eref;

        xd_map = map_to_interval(xd, xd(1), xd(end), 1, 2);

        plot(xd_map, yd, 'b--', 'LineWidth', 1.2, 'HandleVisibility', 'off');
    end

    %% ---------- EPW: Γ-X ----------
    xe = x_epw(idxG_epw:idxX_epw);

    for ib = 1:nbnd
        ye = E_epw(idxG_epw:idxX_epw, ib) - Eref;

        xe_map = map_to_interval(xe, xe(1), xe(end), 0, 1);

        if ib == 1
            plot(xe_map, ye, 'r-', 'LineWidth', 1.5, 'DisplayName', 'EPW');
        else
            plot(xe_map, ye, 'r-', 'LineWidth', 1.5, 'HandleVisibility', 'off');
        end
    end

    %% ---------- EPW: X-U ----------
    xe = x_epw(idxX_epw:idxU_epw);

    for ib = 1:nbnd
        ye = E_epw(idxX_epw:idxU_epw, ib) - Eref;

        xe_map = map_to_interval(xe, xe(1), xe(end), 1, 2);

        plot(xe_map, ye, 'r-', 'LineWidth', 1.5, 'HandleVisibility', 'off');
    end

    %% ---------- 高对称点竖线 ----------
    for xv = xTicks_new
        xline(xv, 'k--', 'LineWidth', 0.8, 'HandleVisibility', 'off');
    end

    %% ---------- 参考能级 ----------
    yline(0, 'k-', 'LineWidth', 0.8, 'HandleVisibility', 'off');

    xlim([0, 2]);
    ylim(yl);

    xticks(xTicks_new);
    xticklabels(xLabels);

    xlabel('Segment-normalized k path');
    ylabel('Energy - E_{ref} (eV)');
    title('DFT vs EPW Interpolated Bands');

    legend('Location', 'northwest');
    set(gca, 'FontSize', 12, 'LineWidth', 1.0);

    hold off;
end

%% =========================================================
%% DFT: 两列 + 空行分 band
%% =========================================================
function bands = read_band_file_blanksep(filename)
    txt = fileread(filename);
    txt = strrep(txt, sprintf('\r\n'), sprintf('\n'));
    blocks = regexp(strtrim(txt), '\n\s*\n', 'split');

    bands = {};
    for i = 1:numel(blocks)
        block = strtrim(blocks{i});
        if isempty(block)
            continue;
        end

        data = sscanf(block, '%f %f', [2, Inf])';

        if ~isempty(data) && size(data,2) == 2
            bands{end+1} = data; %#ok<AGROW>
        end
    end
end

%% =========================================================
%% EPW: 读取 band.eig
%% =========================================================
function [kvec, E] = read_epw_band_eig(filename)
    fid = fopen(filename, 'r');
    if fid < 0
        error('无法打开 EPW band.eig 文件: %s', filename);
    end

    header = strtrim(fgetl(fid));

    tok_nbnd = regexp(header, 'nbnd\s*=\s*(\d+)', 'tokens', 'once');
    tok_nks  = regexp(header, 'nks\s*=\s*(\d+)',  'tokens', 'once');

    if isempty(tok_nbnd) || isempty(tok_nks)
        fclose(fid);
        error('无法从 band.eig 第一行识别 nbnd 和 nks。第一行内容为：%s', header);
    end

    nbnd = str2double(tok_nbnd{1});
    nks  = str2double(tok_nks{1});

    kvec = zeros(nks, 3);
    E = zeros(nks, nbnd);

    for ik = 1:nks
        line_k = fgetl(fid);
        line_e = fgetl(fid);

        if ~ischar(line_k) || ~ischar(line_e)
            fclose(fid);
            error('读取到第 %d 个 k 点时文件提前结束。', ik);
        end

        vk = sscanf(line_k, '%f');
        ve = sscanf(line_e, '%f');

        if numel(vk) ~= 3
            fclose(fid);
            error('第 %d 个 k 点坐标读取失败。line = %s', ik, line_k);
        end

        if numel(ve) ~= nbnd
            fclose(fid);
            error('第 %d 个 k 点的能带数量为 %d，不等于 nbnd = %d。', ...
                ik, numel(ve), nbnd);
        end

        kvec(ik,:) = vk(:).';
        E(ik,:) = ve(:).';
    end

    fclose(fid);
end

%% =========================================================
%% 自动识别路径转折点
%% =========================================================
function turn_idx = detect_turning_points(kvec)
    nks = size(kvec,1);
    turn_idx = 1;

    for i = 2:nks-1
        v1 = kvec(i,:)   - kvec(i-1,:);
        v2 = kvec(i+1,:) - kvec(i,:);

        if norm(v1) > 1e-12 && norm(v2) > 1e-12
            cosang = dot(v1,v2)/(norm(v1)*norm(v2));

            if cosang < 0.99
                turn_idx(end+1) = i; %#ok<AGROW>
            end
        end
    end

    turn_idx(end+1) = nks;
    turn_idx = unique(turn_idx);
end

%% =========================================================
%% 找最近索引
%% =========================================================
function idx = find_closest_idx(x, val)
    [~, idx] = min(abs(x - val));
end

%% =========================================================
%% 检查节点顺序
%% =========================================================
function check_turn_idx(idx, name)
    if numel(idx) ~= 3
        error('%s 节点数量必须为 3：Γ, X, U。', name);
    end

    if ~(idx(1) < idx(2) && idx(2) < idx(3))
        error('%s 节点索引顺序错误，应满足 Γ < X < U。当前为 [%d, %d, %d]', ...
            name, idx(1), idx(2), idx(3));
    end
end

%% =========================================================
%% 线性映射到新区间
%% =========================================================
function xnew = map_to_interval(x, a, b, c, d)
    if abs(b-a) < 1e-12
        xnew = c * ones(size(x));
    else
        xnew = c + (x-a) .* (d-c) ./ (b-a);
    end
end