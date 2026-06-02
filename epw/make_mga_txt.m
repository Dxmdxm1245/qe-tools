G = [0.0, 0.0, 0.0];
X = [0.5, 0.0, 0.5];
U = [0.6250000000, 0.25, 0.625];

n1 = 100;   % G -> X
n2 = 100;   % X -> U

seg1 = [linspace(G(1),X(1),n1)', ...
        linspace(G(2),X(2),n1)', ...
        linspace(G(3),X(3),n1)'];

seg2 = [linspace(X(1),U(1),n2)', ...
        linspace(X(2),U(2),n2)', ...
        linspace(X(3),U(3),n2)'];

% 去掉重复的 X 点
kpath = [seg1; seg2(2:end,:)];

N = size(kpath,1);
w = ones(N,1)/N;

fid = fopen('GXU.txt','w');
fprintf(fid,'%d crystal\n', N);
for i = 1:N
    fprintf(fid,'%.12f %.12f %.12f %.12f\n', ...
        kpath(i,1), kpath(i,2), kpath(i,3), w(i));
end
fclose(fid);