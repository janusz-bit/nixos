{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.my-neovim =
        (inputs.nvf.lib.neovimConfiguration {
          inherit pkgs;
          modules = [
            (
              _:
              {
                config.vim = {
                  theme = {
                    enable = true;
                    name = "gruvbox";
                    style = "dark";
                  };
                  binds.whichKey.enable = true;
                  statusline.lualine.enable = true;
                  telescope.enable = true;
                  autocomplete.nvim-cmp.enable = true;

                  lsp.enable = true;
                  languages = {
                    enableTreesitter = true;
                    nix.enable = true;
                    python.enable = true;
                    clang.enable = true;
                  };
                };
              }
            )
          ];
        }).neovim;
    };
}
