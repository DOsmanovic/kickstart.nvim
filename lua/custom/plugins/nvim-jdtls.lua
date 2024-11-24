return {
  'mfussenegger/nvim-jdtls',
  dependencies = { 'nvim-lua/plenary.nvim' },
  ft = { 'java' }, -- Automatically load for Java files
  opts = function()
    local mason_registry = require 'mason-registry'
    local jdtls_pkg = mason_registry.get_package 'jdtls'
    local jdtls_install_path = jdtls_pkg:get_install_path()

    local lombok_jar = jdtls_install_path .. '/lombok.jar'

    -- Find the path to the Equinox launcher JAR
    local equinox_launcher_jar = vim.fn.glob(jdtls_install_path .. '/plugins/org.eclipse.equinox.launcher_*.jar')
    local equinox_launcher_jar_pattern = jdtls_install_path .. '/plugins/org.eclipse.equinox.launcher_*.jar'
    local equinox_launcher_jars = vim.fn.glob(equinox_launcher_jar_pattern, true, true)

    if not equinox_launcher_jars or #equinox_launcher_jars == 0 then
      vim.notify('Could not find equinox launcher JAR in ' .. jdtls_install_path, vim.log.levels.ERROR)
    else
      equinox_launcher_jar = equinox_launcher_jars[1]
    end
    --vim.notify('equinox_launcher_jar' .. equinox_launcher_jar)
    vim.notify('jdtls_install_path: ' .. jdtls_install_path)

    -- Determine OS-specific configuration
    local config_os
    if vim.fn.has 'mac' == 1 then
      config_os = 'config_mac'
    elseif vim.fn.has 'unix' == 1 then
      config_os = 'config_linux'
    elseif vim.fn.has 'win32' == 1 then
      config_os = 'config_win'
    end
    local config_path = jdtls_install_path .. '/' .. config_os

    -- Set the workspace directory
    local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ':p:h:t')
    local workspace_dir = vim.fn.stdpath 'data' .. '/jdtls-workspace/' .. project_name
    return {
      -- Define the root directory using standard lspconfig
      root_dir = require('lspconfig').util.root_pattern('.git', 'mvnw', 'gradlew', 'pom.xml'),

      -- Command for starting jdtls with Lombok support
      cmd = {
        'java', -- Ensure 'java' is in your system's PATH
        '-Declipse.application=org.eclipse.jdt.ls.core.id1',
        '-Dosgi.bundles.defaultStartLevel=4',
        '-Declipse.product=org.eclipse.jdt.ls.core.product',
        '-Dlog.protocol=true',
        '-Dlog.level=ALL',
        string.format('-javaagent:%s', lombok_jar),
        '-Xms1g',
        '-jar',
        equinox_launcher_jar,
        '-configuration',
        config_path,
        '-data',
        workspace_dir,
      },
      dap = { hotcodereplace = 'auto', config_overrides = {} },
      dap_main = {},
      test = true,
      settings = {
        java = {
          inlayHints = {
            parameterNames = {
              enabled = 'all',
            },
          },
        },
      },
    }
  end,
  config = function(_, opts)
    -- Load extra bundles for nvim-dap if required packages are installed
    local mason_registry = require 'mason-registry'
    local bundles = {} ---@type string[]
    if opts.dap and mason_registry.is_installed 'java-debug-adapter' then
      local java_dbg_pkg = mason_registry.get_package 'java-debug-adapter'
      local java_dbg_path = java_dbg_pkg:get_install_path()
      local jar_patterns = {
        java_dbg_path .. '/extension/server/com.microsoft.java.debug.plugin-*.jar',
      }
      if opts.test and mason_registry.is_installed 'java-test' then
        local java_test_pkg = mason_registry.get_package 'java-test'
        local java_test_path = java_test_pkg:get_install_path()
        vim.list_extend(jar_patterns, {
          java_test_path .. '/extension/server/*.jar',
        })
      end
      for _, jar_pattern in ipairs(jar_patterns) do
        for _, bundle in ipairs(vim.split(vim.fn.glob(jar_pattern), '\n')) do
          table.insert(bundles, bundle)
        end
      end
    end

    local function attach_jdtls()
      local fname = vim.api.nvim_buf_get_name(0)
      local config = vim.tbl_extend('force', {
        cmd = opts.cmd,
        root_dir = opts.root_dir(fname),
        init_options = { bundles = bundles },
        settings = opts.settings,
        capabilities = require('cmp_nvim_lsp').default_capabilities(),
      }, opts.jdtls or {})

      require('jdtls').start_or_attach(config)
    end

    -- Attach jdtls when a Java file is opened
    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'java',
      callback = attach_jdtls,
    })

    -- Keymaps for Java LSP actions
    vim.api.nvim_create_autocmd('LspAttach', {
      callback = function(args)
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if client and client.name == 'jdtls' then
          -- Default keymaps
          local buf = args.buf
          -- vim.api.nvim_buf_set_keymap(buf, "n", "<leader>cxv",
          --     [[<Cmd>lua require('jdtls').extract_variable_all()<CR>]], { desc = "Extract Variable" })
          -- vim.api.nvim_buf_set_keymap(buf, "n", "<leader>cxc",
          --     [[<Cmd>lua require('jdtls').extract_constant()<CR>]], { desc = "Extract Constant" })
          -- vim.api.nvim_buf_set_keymap(buf, "n", "gs", [[<Cmd>lua require('jdtls').super_implementation()<CR>]],
          --     { desc = "Goto Super" })
          -- vim.api.nvim_buf_set_keymap(buf, "n", "<leader>co",
          --     [[<Cmd>lua require('jdtls').organize_imports()<CR>]], { desc = "Organize Imports" })

          -- Keymap to run the main method
          vim.api.nvim_buf_set_keymap(
            buf,
            'n',
            '<leader>cm',
            '<Cmd>lua require("jdtls").run_command("java.project.run")<CR>',
            { desc = 'Run Main Class', noremap = true, silent = true }
          )

          -- Keymap to debug the main method
          vim.api.nvim_buf_set_keymap(
            buf,
            'n',
            '<leader>cD',
            '<Cmd>lua require("jdtls").run_command("java.project.debug")<CR>',
            { desc = 'Debug Main Class', noremap = true, silent = true }
          )

          -- Debug and test mappings if nvim-dap is enabled
          if opts.dap and mason_registry.is_installed 'java-debug-adapter' then
            require('jdtls').setup_dap(opts.dap)
            if opts.test and mason_registry.is_installed 'java-test' then
              vim.api.nvim_buf_set_keymap(buf, 'n', '<leader>tt', [[<Cmd>lua require('jdtls.dap').test_class()<CR>]], { desc = 'Run All Tests' })
              vim.api.nvim_buf_set_keymap(buf, 'n', '<leader>tr', [[<Cmd>lua require('jdtls.dap').test_nearest_method()<CR>]], { desc = 'Run Nearest Test' })
            end
          end
        end
      end,
    })

    -- Attach jdtls initially for the first Java file opened
    attach_jdtls()
  end,
}
