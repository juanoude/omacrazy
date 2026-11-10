return {
    {
        "bjarneo/aether.nvim",
        name = "aether",
        priority = 1000,
        opts = {
            disable_italics = false,
            colors = {
                -- Monotone shades (base00-base07)
                base00 = "#0e091d", -- Default background
                base01 = "#4b2054", -- Lighter background (status bars)
                base02 = "#0e091d", -- Selection background
                base03 = "#4b2054", -- Comments, invisibles
                base04 = "#aa556f", -- Dark foreground
                base05 = "#dc8f7c", -- Default foreground
                base06 = "#dc8f7c", -- Light foreground
                base07 = "#aa556f", -- Light background

                -- Accent colors (base08-base0F)
                base08 = "#c53253", -- Variables, errors, red
                base09 = "#c53253", -- Integers, constants, orange
                base0A = "#ff6565", -- Classes, types, yellow
                base0B = "#a68e5a", -- Strings, green
                base0C = "#8c9785", -- Support, regex, cyan
                base0D = "#6e6080", -- Functions, keywords, blue
                base0E = "#a45782", -- Keywords, storage, magenta
                base0F = "#ff6565", -- Deprecated, brown/yellow
            },
        },
        config = function(_, opts)
            require("aether").setup(opts)
            vim.cmd.colorscheme("aether")

            -- Enable hot reload
            require("aether.hotreload").setup()
        end,
    },
    {
        "LazyVim/LazyVim",
        opts = {
            colorscheme = "aether",
        },
    },
}
