# Copyright 2019 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
"""Verilog parser for locating modules and insances within a source file."""
from pyparsing import *

identifier = Word(alphas+"_", alphanums+"_")

lparen = Suppress("(")
rparen = Suppress(")")
semi = Suppress(";")

param_decl = Literal("#") + nestedExpr()
port_decl = nestedExpr()
param_assigns = Literal("#") + nestedExpr()
port_assigns = nestedExpr()

class Vparse(object):
    """A collection of static methods to perform basic verilog parsing"""
    MOD_STYLE_1995 = 0
    MOD_STYLE_2001 = 1
    def __init__(self):
        pass

    @staticmethod
    def parse_modules(filename):
        module = Suppress("module") + identifier + \
                 Suppress(SkipTo("endmodule")) + Suppress("endmodule")
        module_preamble = Suppress(SkipTo(module))
        modules = OneOrMore(module_preamble + module)
        modules.ignore(cppStyleComment)
        results = modules.parseFile(filename)
        return results

    @staticmethod
    def locate_module(filename, module_type):
        """Locates the module declaration within a Verilog file.
        Args:
          filename: the verilog file
          module_type: the type of module
        Returns:
          A dictionary containing the module type 'mod_type' and the location 'mod_loc'.
          The location is a pair of numbers containing the line number and column number.
        """
        def mod_locate_helper(st, loc, toks):
            mod_loc = [lineno(loc, st), col(loc, st)]
            return [toks[0], mod_loc]

        def port_locate_helper(st, loc, toks):
            # determine if this is a 1995 or 2001 style module declaration
            port_toks = toks[0]
            mod_style = Vparse.MOD_STYLE_1995
            for port_dir in ['input', 'output', 'inout']:
                for t in port_toks:
                    if port_dir == t:
                        mod_style = Vparse.MOD_STYLE_2001
            # TODO: why doesn't this work instead?
            #if any(p in port_toks for p in ['input', 'output', 'inout']):
            #    mod_style = Vparse.MOD_STYLE_2001
            port_loc = [lineno(loc, st), col(loc, st), mod_style]
            return [port_loc]

        module_def = Suppress("module") + \
                     Literal(module_type).setParseAction(mod_locate_helper) + \
                     Suppress(Optional(param_decl)) + \
                     port_decl.setParseAction(port_locate_helper) + semi
        module_find = Suppress(SkipTo(module_def)) + module_def
        module_find.ignore(cppStyleComment)
        results = module_find.parseFile(filename)
        res_dict = {'mod_type' : results[0],
                    'mod_loc'  : results[1],
                    'port_loc' : results[2]}
        return res_dict

    @staticmethod
    def locate_instance(filename, module_type, instance_name):
        """Locates the position of an instantiation within a particular module
        within a Verilog file.
        Args:
          filename: the verilog file
          module_type: the type of module within which to look for the instance
          instance_name: the name of the instance
        Returns:
          A dictionary containing the module type, the instance name and type, and
          the location. The location is a pair containing the line and column numbers.
        """
        def type_locate_helper(st, loc, toks):
            type_loc = [lineno(loc, st), col(loc, st)]
            return [toks[0], type_loc]

        def port_locate_helper(st, loc, toks):
            inst_loc = [lineno(loc, st), col(loc, st)]
            return [inst_loc]

        module_def = Suppress("module") + module_type + \
                     Suppress(Optional(param_decl)) + \
                     Suppress(port_decl + semi)

        instance = Group(identifier.setParseAction(type_locate_helper) + \
                         Optional(Suppress(param_assigns)) + instance_name + \
                         Suppress(port_assigns).setParseAction(port_locate_helper) + semi)

        go = Suppress(SkipTo(module_def)) + module_def + \
             Suppress(SkipTo(instance)) + instance
        go.ignore(cppStyleComment)
        results = go.parseFile(filename)
        res_dict = {'mod_type' : results[0],
                    'inst_type': results[1][0],
                    'inst_type_loc': results[1][1],
                    'inst_name'    : results[1][2],
                    'port_loc'     : results[1][3]}
        return res_dict

    @staticmethod
    def locate_declaration(filename, module_type):
        """Locates the position within a verilog module's body where top-level declaration
        statements can occur. This ends up being after the portlist, but before any other
        net or instance declarations.
        Args:
          filename: the verilog file
          module_type: the type of module (in case there is more than one module
                       defined in the verilog file).
        Returns:
          A dictionary containing the location 'declaration_loc', which is a pair of numbers
          containing the line number and column number.
        """
        def locate_helper(st, loc, toks):
            return [[lineno(loc, st), col(loc, st)]]

        module_def = Suppress("module") + module_type + \
                     Suppress(Optional(param_decl)) + \
                     Suppress(port_decl) + Suppress(semi).setParseAction(locate_helper)
        go = Suppress(SkipTo(module_def)) + module_def
        go.ignore(cppStyleComment)
        results = go.parseFile(filename)
        res_dict = {'declaration_loc' : results[1]}
        return res_dict

    @staticmethod
    def locate_endmodule(filename, module_type):
        """Locates the 'endmodule' keyword for a particular module within a Verilog file.
        Args:
          filename: the verilog file
          module_type: the type of module (in case there is more than one module
                       defined in the verilog file).
        Returns:
          A dictionary containing the location 'endmodule_loc', which is a pair of numbers
          containing the line number and column number.
        """
        def locate_helper(st, loc, toks):
            return [[lineno(loc, st), col(loc, st)]]

        module_def = Suppress("module") + module_type + \
                     Suppress(Optional(param_decl)) + \
                     Suppress(port_decl) + Suppress(semi)
        go = Suppress(SkipTo(module_def)) + module_def + \
             Suppress(SkipTo("endmodule")) + Literal("endmodule").setParseAction(locate_helper)
        go.ignore(cppStyleComment)
        results = go.parseFile(filename)
        res_dict = {'endmodule_loc' : results[1]}
        return res_dict

    @staticmethod
    def check_net_type(filename, net_name):
        """Checks if the net is declared as a single-bit net or a multi-bit vector.
        Args:
          filename: the veriog file to search in
          net_name: the name of the net
        Returns:
          "none"   : if the net could not be found in the file
          "single" : if the net is declared as a single bit without a range
          "vector" : if the net is declared as a multi-bit vector, defined
                     with a bit range [x:x]
        """
        # helper function to insert a specific string into the parse results
        # so we can later identify if the net was declared as a multi-bit vector
        def vector_helper(st, loc, toks):
            return "net_is_a_vector"

        # define parsing rules to identify a net declaration in the verilog code
        range_decl = "[" + SkipTo(":") + ":" + SkipTo("]") + "]"
        # enum_type = "enum" + Suppress(delimitedList()....
        net_type = oneOf("wire reg logic")
        port_type = oneOf("input output inout")
        net_list = delimitedList(identifier + Optional(range_decl))
        net_def = Suppress(net_type) + \
                  Optional(OneOrMore(
                      range_decl.setParseAction(vector_helper))) + \
                  net_list
        port_def = Suppress(port_type) + Suppress(Optional(net_type)) + \
                   Optional(range_decl.setParseAction(vector_helper)) + identifier
        sig_def = net_def | port_def
        sig_def.ignore(cppStyleComment)

        # instead of trying to match the entire file to our parse rules with
        # the 'parseFile' function, we use 'scanString' to find only the text
        # that matches our net definition rule. Then we loop through the
        # results and find the declaration that includes the net name we care
        # about. Finally, we look at the parse results to determine if the net
        # marked as a vector.
        source = open(filename).read()
        for token, start, end in sig_def.scanString(source):
            # convert ParseResults object to a regular list
            token_list = token.asList()
            if net_name in token_list:
                if "net_is_a_vector" in token_list:
                    return "vector"
                else:
                    return "single"
        return "none"
