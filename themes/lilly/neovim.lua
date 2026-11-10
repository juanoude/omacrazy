return {
    {
        "bjarneo/aether.nvim",
        branch = "v2",
        name = "aether",
        priority = 1000,
        opts = {
            transparent = false,
            colors = {
                -- Background colors
                bg = "#162533",
                bg_dark = "#162533",
                bg_highlight = "#3b4957",

                -- Foreground colors
                -- fg: Object properties, builtin types, builtin variables, member access, default text
                fg = "#d9607d",
                -- fg_dark: Inactive elements, statusline, secondary text
                fg_dark = "#ee5b6e",
                -- comment: Line highlight, gutter elements, disabled states
                comment = "#3b4957",

                -- Accent colors
                -- red: Errors, diagnostics, tags, deletions, breakpoints
                red = "#9c413e",
                -- orange: Constants, numbers, current line number, git modifications
                orange = "#c6615e",
                -- yellow: Types, classes, constructors, warnings, numbers, booleans
                yellow = "#d92640",
                -- green: Comments, strings, success states, git additions
                green = "#29a0d6",
                -- cyan: Parameters, regex, preprocessor, hints, properties
                cyan = "#349bcb",
                -- blue: Functions, keywords, directories, links, info diagnostics
                blue = "#6a6a95",
                -- purple: Storage keywords, special keywords, identifiers, namespaces
                purple = "#96698e",
                -- magenta: Function declarations, exception handling, tags
                magenta = "#c4a8c0",
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
