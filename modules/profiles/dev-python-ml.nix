{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    (python3.withPackages (ps: with ps; [
      numpy
      pandas
      matplotlib
      scikit-learn
      ipython
      jupyter
      # torch  # large; uncomment when needed
    ]))
    uv
  ];
}
