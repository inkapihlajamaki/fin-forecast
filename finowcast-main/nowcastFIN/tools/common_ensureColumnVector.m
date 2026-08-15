function colVec = common_ensureColumnVector(vec)
% Ensures that a vector is expressed as a Nx1 vector
%
% INPUT
% - vec [array] = input vector (of dimensions 1xN or Nx1)
%
% OUTPUT
% - colVec [array] = vector of dimension Nx1
%

    % Ensure input is a vector
    if ~isvector(vec)
        error('Input must be a vector.');
    end
    
    % Reshape the vector into a column vector
    colVec = vec(:);

end