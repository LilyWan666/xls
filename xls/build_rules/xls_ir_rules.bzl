# Copyright 2021 The XLS Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""This module contains IR-related build rules for XLS."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    "//xls/build_rules:xls_common_rules.bzl",
    "append_cmd_line_args_to",
    "get_args",
    "get_output_filename_value",
)
load("//xls/build_rules:xls_config_rules.bzl", "CONFIG")
load(
    "//xls/build_rules:xls_providers.bzl",
    "ConvIRInfo",
    "DslxInfo",
    "DslxModuleInfo",
    "OptIRInfo",
)
load(
    "//xls/build_rules:xls_toolchains.bzl",
    "get_xls_toolchain_info",
    "xls_toolchain_attr",
)

_DEFAULT_IR_EVAL_TEST_ARGS = {
    "random_inputs": "100",
    "optimize_ir": "true",
}

_DEFAULT_BENCHMARK_IR_ARGS = {}

_IR_FILE_EXTENSION = ".ir"

_OPT_IR_FILE_EXTENSION = ".opt.ir"

def append_xls_dslx_ir_generated_files(args, basename):
    """Returns a dictionary of arguments appended with filenames generated by the 'xls_dslx_ir' rule.

    Args:
      args: A dictionary of arguments.
      basename: The file basename.

    Returns:
      Returns a dictionary of arguments appended with filenames generated by the 'xls_dslx_ir' rule.
    """
    args.setdefault("ir_file", basename + _IR_FILE_EXTENSION)
    return args

def get_xls_dslx_ir_generated_files(args):
    """Returns a list of filenames generated by the 'xls_dslx_ir' rule found in 'args'.

    Args:
      args: A dictionary of arguments.

    Returns:
      Returns a list of files generated by the 'xls_dslx_ir' rule found in 'args'.
    """
    return [args.get("ir_file")]

def append_xls_ir_opt_ir_generated_files(args, basename):
    """Returns a dictionary of arguments appended with filenames generated by the 'xls_ir_opt_ir' rule.

    Args:
      args: A dictionary of arguments.
      basename: The file basename.

    Returns:
      Returns a dictionary of arguments appended with filenames generated by the 'xls_ir_opt_ir' rule.
    """
    args.setdefault("opt_ir_file", basename + _OPT_IR_FILE_EXTENSION)
    return args

def get_xls_ir_opt_ir_generated_files(args):
    """Returns a list of filenames generated by the 'xls_ir_opt_ir' rule found in 'args'.

    Args:
      args: A dictionary of arguments.

    Returns:
      Returns a list of files generated by the 'xls_ir_opt_ir' rule found in 'args'.
    """
    return [args.get("opt_ir_file")]

def _add_entry_attr(
        ctx,
        arguments,
        argument_name,
        universal_entry_value = None):
    """Using a priority scheme, adds the entry point to the 'arguments'.

    The entry point value can come from three location:
        local - argument list (highest priority)
        global - the rule's context
        universal - outside the rule's context (lowest priority)

    The entry point value is added to the 'arguments' using the priority scheme.

    Args:
      ctx: The current rule's context object.
      arguments: The arguments dictionary.
      argument_name: The argument name to lookup in the arguments dictionary.
      universal_entry_value: The 'universal' entry point value. The value is
        outside the rule's context.

    Returns:
      If the entry value is present in one of the locations, a copy of the
      argument dictionary with the entry point value added. Otherwise, return
      the argument dictionary untouched.
    """
    my_arguments = dict(arguments)
    if argument_name not in my_arguments:
        if hasattr(ctx.attr, "entry") and ctx.attr.entry != "":
            my_arguments[argument_name] = ctx.attr.entry
        elif universal_entry_value:
            my_arguments[argument_name] = universal_entry_value
    return my_arguments

def _convert_to_ir(ctx, src, dep_src_list):
    """Converts a DSLX source file to an IR file.

    Creates an action in the context to convert a DSLX source file to an
    IR file.

    Args:
      ctx: The current rule's context object.
      src: The source file.
      dep_src_list: A list of source file dependencies.
    Returns:
      A File referencing the IR file.
    """
    ir_converter_tool = get_xls_toolchain_info(ctx).ir_converter_tool
    IR_CONV_FLAGS = (
        "entry",
        "dslx_path",
        "emit_fail_as_assert",
    )

    ir_conv_args = dict(ctx.attr.ir_conv_args)
    ir_conv_args["dslx_path"] = (
        ir_conv_args.get("dslx_path", "") + ":${PWD}:" +
        ctx.genfiles_dir.path + ":" + ctx.bin_dir.path
    )

    my_args = get_args(ir_conv_args, IR_CONV_FLAGS)

    required_files = [src] + dep_src_list
    required_files += get_xls_toolchain_info(ctx).dslx_std_lib_list

    ir_filename = get_output_filename_value(
        ctx,
        "ir_file",
        ctx.attr.name + _IR_FILE_EXTENSION,
    )
    ir_file = ctx.actions.declare_file(ir_filename)

    ctx.actions.run_shell(
        outputs = [ir_file],
        # The IR converter executable is a tool needed by the action.
        tools = [ir_converter_tool],
        # The files required for converting the DSLX source file.
        inputs = required_files + [ir_converter_tool],
        command = "{} {} {} > {}".format(
            ir_converter_tool.path,
            my_args,
            src.path,
            ir_file.path,
        ),
        mnemonic = "ConvertDSLX",
        progress_message = "Converting DSLX file: %s" % (src.path),
    )
    return ir_file

def _optimize_ir(ctx, src):
    """Optimizes an IR file.

    Creates an action in the context to optimize an IR file.

    Args:
      ctx: The current rule's context object.
      src: The source file.

    Returns:
      A File referencing the optimized IR file.
    """
    opt_ir_tool = get_xls_toolchain_info(ctx).opt_ir_tool
    opt_ir_args = ctx.attr.opt_ir_args
    IR_OPT_FLAGS = (
        "entry",
        "ir_dump_path",
        "run_only_passes",
        "skip_passes",
        "opt_level",
    )

    my_args = get_args(opt_ir_args, IR_OPT_FLAGS)

    opt_ir_filename = get_output_filename_value(
        ctx,
        "opt_ir_file",
        ctx.attr.name + _OPT_IR_FILE_EXTENSION,
    )
    opt_ir_file = ctx.actions.declare_file(opt_ir_filename)
    ctx.actions.run_shell(
        outputs = [opt_ir_file],
        # The IR optimization executable is a tool needed by the action.
        tools = [opt_ir_tool],
        # The files required for optimizing the IR file.
        inputs = [src, opt_ir_tool],
        command = "{} {} {} > {}".format(
            opt_ir_tool.path,
            src.path,
            my_args,
            opt_ir_file.path,
        ),
        mnemonic = "OptimizeIR",
        progress_message = "Optimizing IR file: %s" % (src.path),
    )
    return opt_ir_file

def get_ir_equivalence_test_cmd(
        ctx,
        src_0,
        src_1,
        entry = None,
        append_cmd_line_args = True):
    """
    Returns the runfiles and command that executes in the ir_equivalence_test rule.

    Args:
      ctx: The current rule's context object.
      src_0: A file for the test.
      src_1: A file for the test.
      entry: The 'universal' entry: the value from outside the rule's context.
        The value can be overwritten by the entry attribute of the rule's
        context. Typically, the value is from another rule. For example, assume
        this function is used within rule B, where rule B depends on rule A, the
        value is from rule A.
      append_cmd_line_args: Flag controlling appending the command-line
        arguments invoking the command generated by this function. When set to
        True, the command-line arguments invoking the command are appended.
        Otherwise, the command-line arguments are not appended.

    Returns:
      A tuple with two elements. The first element is a list of runfiles to
      execute the command. The second element is the command.
    """
    ir_equivalence_tool = get_xls_toolchain_info(ctx).ir_equivalence_tool
    IR_EQUIVALENCE_FLAGS = (
        # Overrides global entry attribute.
        "function",
        "timeout",
    )

    ir_equivalence_args = dict(ctx.attr.ir_equivalence_args)

    # If "function" not defined in arguments, use global "entry" attribute.
    ir_equivalence_args = _add_entry_attr(
        ctx,
        ir_equivalence_args,
        "function",
        entry,
    )

    my_args = get_args(ir_equivalence_args, IR_EQUIVALENCE_FLAGS)

    cmd = "{} {} {} {}\n".format(
        ir_equivalence_tool.short_path,
        src_0.short_path,
        src_1.short_path,
        my_args,
    )

    # Append command-line arguments.
    if append_cmd_line_args:
        cmd = append_cmd_line_args_to(cmd)

    # The required runfiles are the source files and the IR equivalence tool
    # executable.
    runfiles = [src_0, src_1, ir_equivalence_tool]
    return runfiles, cmd

def get_eval_ir_test_cmd(ctx, src, entry = None, append_cmd_line_args = True):
    """Returns the runfiles and command that executes in the xls_eval_ir_test rule.

    Args:
      ctx: The current rule's context object.
      src: The file to test.
      entry: The 'universal' entry: the value from outside the rule's context.
        The value can be overwritten by the entry attribute of the rule's
        context. Typically, the value is from another rule. For example, assume
        this function is used within rule B, where rule B depends on rule A, the
        value is from rule A.
      append_cmd_line_args: Flag controlling appending the command-line
        arguments invoking the command generated by this function. When set to
        True, the command-line arguments invoking the command are appended.
        Otherwise, the command-line arguments are not appended.

    Returns:
      A tuple with two elements. The first element is a list of runfiles to
      execute the command. The second element is the command.
    """
    ir_eval_tool = get_xls_toolchain_info(ctx).ir_eval_tool
    ir_eval_default_args = _DEFAULT_IR_EVAL_TEST_ARGS
    IR_EVAL_FLAGS = (
        # Overrides global entry attribute.
        "entry",
        "input",
        "input_file",
        "random_inputs",
        "expected",
        "expected_file",
        "optimize_ir",
        "eval_after_each_pass",
        "use_llvm_jit",
        "test_llvm_jit",
        "llvm_opt_level",
        "test_only_inject_jit_result",
        "input_validator_expr",
        "input_validator_path",
    )

    ir_eval_args = dict(ctx.attr.ir_eval_args)

    # If "entry" not defined in arguments, use global "entry" attribute.
    ir_eval_args = _add_entry_attr(ctx, ir_eval_args, "entry", entry)

    runfiles = []
    if ctx.attr.input_validator:
        validator_info = ctx.attr.input_validator[DslxModuleInfo]
        ir_eval_args["input_validator_path"] = validator_info.dslx_source_module_file.short_path
        runfiles.append(validator_info.dslx_source_module_file)
        runfiles = runfiles + validator_info.dslx_source_files
    elif ctx.attr.input_validator_expr:
        ir_eval_args["input_validator_expr"] = "\"" + ctx.attr.input_validator_expr + "\""

    my_args = get_args(ir_eval_args, IR_EVAL_FLAGS, ir_eval_default_args)

    cmd = "{} {} {}".format(
        ir_eval_tool.short_path,
        src.short_path,
        my_args,
    )

    # Append command-line arguments.
    if append_cmd_line_args:
        cmd = append_cmd_line_args_to(cmd)

    # The required runfiles are the source file and the IR interpreter tool
    # executable.
    runfiles = runfiles + [src, ir_eval_tool]
    return runfiles, cmd

def get_benchmark_ir_cmd(ctx, src, entry = None, append_cmd_line_args = True):
    """Returns the runfiles and command that executes in the xls_benchmark_ir rule.

    Args:
      ctx: The current rule's context object.
      src: The file to benchmark.
      entry: The 'universal' entry: the value from outside the rule's context.
        The value can be overwritten by the entry attribute of the rule's
        context. Typically, the value is from another rule. For example, assume
        this function is used within rule B, where rule B depends on rule A, the
        value is from rule A.
      append_cmd_line_args: Flag controlling appending the command-line
        arguments invoking the command generated by this function. When set to
        True, the command-line arguments invoking the command are appended.
        Otherwise, the command-line arguments are not appended.

    Returns:
      A tuple with two elements. The first element is a list of runfiles to
      execute the command. The second element is the command.
    """
    benchmark_ir_tool = get_xls_toolchain_info(ctx).benchmark_ir_tool
    BENCHMARK_IR_FLAGS = (
        "clock_period_ps",
        "pipeline_stages",
        "clock_margin_percent",
        "show_known_bits",
        # Overrides global entry attribute.
        "entry",
        "delay_model",
    )

    benchmark_ir_args = dict(ctx.attr.benchmark_ir_args)

    # If "entry" not defined in arguments, use global "entry" attribute.
    benchmark_ir_args = _add_entry_attr(ctx, benchmark_ir_args, "entry", entry)

    my_args = get_args(
        benchmark_ir_args,
        BENCHMARK_IR_FLAGS,
        _DEFAULT_BENCHMARK_IR_ARGS,
    )

    cmd = "{} {} {}".format(
        benchmark_ir_tool.short_path,
        src.short_path,
        my_args,
    )

    # Append command-line arguments.
    if append_cmd_line_args:
        cmd = append_cmd_line_args_to(cmd)

    # The required runfiles are the source files and the IR benchmark tool
    # executable.
    runfiles = [src, benchmark_ir_tool]
    return runfiles, cmd

def get_mangled_ir_symbol(module_name, function_name, parametric_values = None):
    """Returns the mangled IR symbol for the module/function combination.

    "Mangling" is the process of turning nicely namedspaced symbols into
    "grosser" (mangled) flat (non hierarchical) symbol, e.g. that lives on a
    package after IR conversion. To retrieve/execute functions that have been IR
    converted, we use their mangled names to refer to them in the IR namespace.

    Args:
      module_name: The DSLX module name that the function is within.
      function_name: The DSLX function name within the module.
      parametric_values: Any parametric values used for instantiation (e.g. for
        a parametric entry point that is known to be instantiated in the IR
        converted module). This is generally for more advanced use cases like
        internals testing.

    Returns:
      The "mangled" symbol string.
    """
    parametric_values_str = ""

    if parametric_values:
        parametric_values_str = "__" + "_".join(
            [
                str(v)
                for v in parametric_values
            ],
        )
    return "__" + module_name + "__" + function_name + parametric_values_str

# Global entry attribute. It can be overwritten by a local argument
# representative.
xls_entry_attrs = {
    "entry": attr.string(
        doc = "The (*mangled*) name of the entry point. See " +
              "get_mangled_ir_symbol. The value is applied to the rule " +
              "context. It can be overwritten by a local argument.",
        default = "",
    ),
}

xls_ir_common_attrs = {
    "src": attr.label(
        doc = "The IR source file for the rule. A single source file must be " +
              "provided. The file must have a '.ir' extension.",
        mandatory = True,
        allow_single_file = [_IR_FILE_EXTENSION],
    ),
}

xls_dslx_ir_attrs = {
    # TODO (vmirian) 01-25-2022 Remove attribute when xls_dslx_module_library is
    # removed.
    "dep": attr.label(
        doc = "DO NOT USE. This attribute will be deprecated. A dependency " +
              "target for the rule. The target must emit a DslxModuleInfo " +
              "provider. ",
        providers = [DslxModuleInfo],
    ),
    # TODO (vmirian) 01-25-2022 Make mandatory when xls_dslx_module_library is
    # removed.
    "srcs": attr.label_list(
        doc = "Top level source files for the conversion. Files must have a " +
              " '.x' extension. There must be single source file.",
        allow_files = [".x"],
    ),
    "deps": attr.label_list(
        doc = "Dependency targets for the rule. The targets must emit a " +
              "DslxInfo provider.",
        providers = [DslxInfo],
    ),
    "ir_conv_args": attr.string_dict(
        doc = "Arguments of the IR conversion tool. For details on the" +
              "arguments, refer to the ir_converter_main application at" +
              "//xls/dslx/ir_converter_main.cc. When the " +
              "default XLS toolchain differs from the default toolchain, " +
              "the application target may be different.",
    ),
    "ir_file": attr.output(
        doc = "Filename of the generated IR. If not specified, the " +
              "target name of the bazel rule followed by an " +
              _IR_FILE_EXTENSION + " extension is used.",
    ),
}

def xls_dslx_ir_impl(ctx):
    """The implementation of the 'xls_dslx_ir' rule.

    Converts a DSLX source file to an IR file.

    Args:
      ctx: The current rule's context object.

    Returns:
      DslxModuleInfo provider
      ConvIRInfo provider
      DefaultInfo provider
    """
    src = None
    dep_src_list = []
    dep = ctx.attr.dep
    srcs = ctx.files.srcs
    deps = ctx.attr.deps

    # TODO (vmirian) 01-25-2022 Remove if statement when xls_dslx_module_library
    # is removed.
    if dep and (srcs or deps):
        fail("One of: 'dep' or ['srcs', 'deps'] must be assigned.")

    if srcs and len(srcs) != 1:
        fail("A single source file must be specified.")

    # TODO (vmirian) 01-25-2022 Remove if statement when xls_dslx_module_library
    # is removed.
    if dep:
        src = ctx.attr.dep[DslxModuleInfo].dslx_source_module_file
        dep_src_list = (
            ctx.attr.dep[DslxModuleInfo].dslx_source_files
        )
    else:
        src = srcs[0]
        dep_src_list = []
        for dep in deps:
            dep_src_list += dep[DslxInfo].dslx_source_files.to_list()

    ir_file = _convert_to_ir(ctx, src, dep_src_list)

    # TODO (vmirian) 01-25-2022 Remove when xls_dslx_module_library is removed.
    dslx_module_info = DslxModuleInfo(
        dslx_source_files = dep_src_list,
        dslx_source_module_file = src,
    )
    return [
        dslx_module_info,
        ConvIRInfo(
            conv_ir_file = ir_file,
        ),
        DefaultInfo(files = depset([ir_file])),
    ]

xls_dslx_ir = rule(
    doc = """
        A build rule that converts a DSLX source file to an IR file.

        Examples:

        1) A simple IR conversion.
            # Assume a xls_dslx_library target bc_dslx is present.
            xls_dslx_ir(
                name = "d_ir",
                srcs = ["d.x"],
                deps = [":bc_dslx"],
            )

        2) An IR conversion with an entry defined.
            xls_dslx_ir(
                name = "d_ir",
                srcs = ["d.x"],
                deps = [":bc_dslx"],
                ir_conv_args = {
                    "entry" : "d",
                },
            )

        3) An IR conversion on a xls_dslx_module_library.
            xls_dslx_module_library(
                name = "a_dslx_module",
                src = "a.x",
            )

            xls_dslx_ir(
                name = "a_ir",
                dep = ":a_dslx_module",
            )
    """,
    implementation = xls_dslx_ir_impl,
    attrs = dicts.add(
        xls_dslx_ir_attrs,
        CONFIG["xls_outs_attrs"],
        xls_toolchain_attr,
    ),
)

def xls_ir_opt_ir_impl(ctx, src):
    """The implementation of the 'xls_ir_opt_ir' rule.

    Optimizes an IR file.

    Args:
      ctx: The current rule's context object.
      src: The source file.

    Returns:
      OptIRInfo provider
      DefaultInfo provider
    """
    opt_ir_file = _optimize_ir(ctx, src)

    return [
        OptIRInfo(
            input_ir_file = src,
            opt_ir_file = opt_ir_file,
            opt_ir_args = ctx.attr.opt_ir_args,
        ),
        DefaultInfo(files = depset([opt_ir_file])),
    ]

xls_ir_opt_ir_attrs = {
    "opt_ir_args": attr.string_dict(
        doc = "Arguments of the IR optimizer tool. For details on the" +
              "arguments, refer to the opt_main application at" +
              "//xls/tools/opt_main.cc. When the " +
              "default XLS toolchain differs from the default toolchain, " +
              "the application target may be different.",
    ),
    "opt_ir_file": attr.output(
        doc = "Filename of the generated optimized IR. If not specified, the " +
              "target name of the bazel rule followed by an " +
              _OPT_IR_FILE_EXTENSION + " extension is used.",
    ),
}

def _xls_ir_opt_ir_impl_wrapper(ctx):
    """The implementation of the 'xls_ir_opt_ir' rule.

    Wrapper for xls_ir_opt_ir_impl. See: xls_ir_opt_ir_impl.

    Args:
      ctx: The current rule's context object.
    Returns:
      See: xls_ir_opt_ir_impl.
    """
    return xls_ir_opt_ir_impl(ctx, ctx.file.src)

xls_ir_opt_ir = rule(
    doc = """
        A build rule that optimizes an IR file.

        Examples:

        1) Optimizing an IR file with an entry defined.
            xls_ir_opt_ir(
                name = "a_opt_ir",
                src = "a.ir",
                opt_ir_args = {
                    "entry" : "a",
                },
            )

        2) A target as the source.
            xls_dslx_ir(
                name = "a_ir",
                dep = ":a_dslx_module",
            )

            xls_ir_opt_ir(
                name = "a_opt_ir",
                src = ":a_ir",
            )
    """,
    implementation = _xls_ir_opt_ir_impl_wrapper,
    attrs = dicts.add(
        xls_ir_common_attrs,
        xls_ir_opt_ir_attrs,
        CONFIG["xls_outs_attrs"],
        xls_toolchain_attr,
    ),
)

def _xls_ir_equivalence_test_impl(ctx):
    """The implementation of the 'xls_ir_equivalence_test' rule.

    Executes the equivalence tool on two IR files.

    Args:
      ctx: The current rule's context object.

    Returns:
      DefaultInfo provider
    """
    ir_file_a = ctx.file.src_0
    ir_file_b = ctx.file.src_1
    runfiles, cmd = get_ir_equivalence_test_cmd(ctx, ir_file_a, ir_file_b)
    executable_file = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(
        output = executable_file,
        content = "\n".join([
            "#!/bin/bash",
            "set -e",
            cmd,
            "exit 0",
        ]),
        is_executable = True,
    )

    return [
        DefaultInfo(
            runfiles = ctx.runfiles(files = runfiles),
            files = depset([executable_file]),
            executable = executable_file,
        ),
    ]

_two_ir_files_attrs = {
    "src_0": attr.label(
        doc = "An IR source file for the rule. A single source file must be " +
              "provided. The file must have a '.ir' extension.",
        mandatory = True,
        allow_single_file = [_IR_FILE_EXTENSION],
    ),
    "src_1": attr.label(
        doc = "An IR source file for the rule. A single source file must be " +
              "provided. The file must have a '.ir' extension.",
        mandatory = True,
        allow_single_file = [_IR_FILE_EXTENSION],
    ),
}

xls_ir_equivalence_test_attrs = {
    "ir_equivalence_args": attr.string_dict(
        doc = "Arguments of the IR equivalence tool. For details on the " +
              "arguments, refer to the check_ir_equivalence_main application " +
              "at //xls/tools/check_ir_equivalence_main.cc. " +
              "When the default XLS toolchain differs from the default " +
              "toolchain, the application target may be different.",
    ),
}

xls_ir_equivalence_test = rule(
    doc = """An IR equivalence test executes the equivalence tool on two IR files.

        Example:

        1) A file as the source.
            xls_ir_equivalence_test(
                name = "ab_ir_equivalence_test",
                src_0 = "a.ir",
                src_1 = "b.ir",
            )

        2) A target as the source.
            xls_dslx_ir(
                name = "b_ir",
                dep = ":b_dslx_module",
            )

            xls_ir_equivalence_test(
                name = "ab_ir_equivalence_test",
                src_0 = "a.ir",
                src_1 = ":b_ir",
            )
    """,
    implementation = _xls_ir_equivalence_test_impl,
    attrs = dicts.add(
        _two_ir_files_attrs,
        xls_ir_equivalence_test_attrs,
        xls_entry_attrs,
        xls_toolchain_attr,
    ),
    test = True,
)

def _xls_eval_ir_test_impl(ctx):
    """The implementation of the 'xls_eval_ir_test' rule.

    Executes the IR Interpreter on an IR file.

    Args:
      ctx: The current rule's context object.
    Returns:
      DefaultInfo provider
    """
    if ctx.attr.input_validator and ctx.attr.input_validator_expr:
        fail(msg = "Only one of \"input_validator\" or \"input_validator_expr\" " +
                   "may be specified for a single \"xls_eval_ir_test\" rule.")
    src = ctx.file.src
    runfiles, cmd = get_eval_ir_test_cmd(ctx, src)
    executable_file = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(
        output = executable_file,
        content = "\n".join([
            "#!/bin/bash",
            "set -e",
            cmd,
            "exit 0",
        ]),
        is_executable = True,
    )

    return [
        DefaultInfo(
            runfiles = ctx.runfiles(files = runfiles),
            files = depset([executable_file]),
            executable = executable_file,
        ),
    ]

xls_eval_ir_test_attrs = {
    "input_validator": attr.label(
        doc = "The target defining the input validator for this test. " +
              "Mutually exclusive with \"input_validator_expr\".",
        providers = [DslxModuleInfo],
        allow_files = True,
    ),
    "input_validator_expr": attr.string(
        doc = "The expression to validate an input for the test function. " +
              "Mutually exclusive with \"input_validator\".",
    ),
    "ir_eval_args": attr.string_dict(
        doc = "Arguments of the IR interpreter. For details on the " +
              "arguments, refer to the eval_ir_main application at " +
              "//xls/tools/eval_ir_main.cc. When the default XLS " +
              "toolchain differs from the default toolchain, the application " +
              "target may be different.",
        default = _DEFAULT_IR_EVAL_TEST_ARGS,
    ),
}

xls_eval_ir_test = rule(
    doc = """A IR evaluation test executes the IR interpreter on an IR file.

        Example:

         1) A file as the source.
            xls_eval_ir_test(
                name = "a_eval_ir_test",
                src = "a.ir",
            )

        2) An xls_ir_opt_ir target as the source.
            xls_ir_opt_ir(
                name = "a_opt_ir",
                src = "a.ir",
            )


            xls_eval_ir_test(
                name = "a_eval_ir_test",
                src = ":a_opt_ir",
            )
    """,
    implementation = _xls_eval_ir_test_impl,
    attrs = dicts.add(
        xls_ir_common_attrs,
        xls_eval_ir_test_attrs,
        xls_entry_attrs,
        xls_toolchain_attr,
    ),
    test = True,
)

def _xls_benchmark_ir_impl(ctx):
    """The implementation of the 'xls_benchmark_ir' rule.

    Executes the benchmark tool on an IR file.

    Args:
      ctx: The current rule's context object.
    Returns:
      DefaultInfo provider
    """
    src = ctx.file.src
    runfiles, cmd = get_benchmark_ir_cmd(ctx, src)
    executable_file = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(
        output = executable_file,
        content = "\n".join([
            "#!/bin/bash",
            "set -e",
            cmd,
            "exit 0",
        ]),
        is_executable = True,
    )

    return [
        DefaultInfo(
            runfiles = ctx.runfiles(files = runfiles),
            files = depset([executable_file]),
            executable = executable_file,
        ),
    ]

xls_benchmark_ir_attrs = {
    "benchmark_ir_args": attr.string_dict(
        doc = "Arguments of the benchmark IR tool. For details on the " +
              "arguments, refer to the benchmark_main application at " +
              "//xls/tools/benchmark_main.cc. When the default " +
              "XLS toolchain differs from the default toolchain, the " +
              "application target may be different.",
    ),
}

xls_benchmark_ir = rule(
    doc = """A IR benchmark executes the benchmark tool on an IR file.

        Example:

         1) A file as the source.
            xls_benchmark_ir(
                name = "a_benchmark",
                src = "a.ir",
            )

        2) An xls_ir_opt_ir target as the source.
            xls_ir_opt_ir(
                name = "a_opt_ir",
                src = "a.ir",
            )


            xls_benchmark_ir(
                name = "a_benchmark",
                src = ":a_opt_ir",
            )
    """,
    implementation = _xls_benchmark_ir_impl,
    attrs = dicts.add(
        xls_ir_common_attrs,
        xls_benchmark_ir_attrs,
        xls_entry_attrs,
        xls_toolchain_attr,
    ),
    executable = True,
)
