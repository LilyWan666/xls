"""A tool to visualize XLS IR.

Exposes a text box to edit or cut-and-paste XLS IR to render as a graph.
"""

import functools
import json
import os
import subprocess
import sys
import tempfile
import dgl  # or import necessary PyGEO modules


from typing import List, Tuple

from absl import app
from absl import flags

import flask
import werkzeug.exceptions
import werkzeug.security

from xls.common import runfiles
from xls.common.python import init_xls
from xls.visualization.ir_viz.python import ir_to_json

FLAGS = flags.FLAGS
flags.DEFINE_bool('use_ipv6', False, 'Whether to use IPv6.')
flags.DEFINE_integer('port', None, 'Port to serve on.')
flags.DEFINE_string('delay_model', None, 'Delay model to use.')
# TODO(meheff): Remove this flag and figure out a better way getting the actual
# schedule used in the examples and/or surface the scheduling options in the
# UI.
flags.DEFINE_integer(
    'pipeline_stages', None,
    'Schedule the IR function into this many stages using the specified '
    'delay model. This influence the rendering graph by changing '
    'cycle-spanning edges to dotted style')
flags.DEFINE_string(
    'preload_ir_path', None, 'Path to local IR file to render on startup. If '
    '"-" then read from stdin.')
flags.DEFINE_string(
    'example_ir_dir', None, 'Path to directory containing IR files to use as '
    'precanned examples available in the UI via the "Examples" drop down menu. '
    'All files ending in ".ir" in the directory are used.')
# TODO(meheff): the function should be selectable via the UI.
flags.DEFINE_string(
    'top', None, 'Name of entity (function, proc, etc) to visualize. If not '
    'given then the entity specified as top in the IR file is visualzied.')
# flags.mark_flag_as_required('delay_model')

IR_EXAMPLES_FILE_LIST = 'xls/visualization/ir_viz/ir_examples_file_list.txt'

# webapp = flask.Flask('XLS UI')
# webapp.debug = True

# Set of pre-canned examples as a list of (name, IR text) tuples. By default
# these are loaded from IR_EXAMPLES_FILE_LIST unless --example_ir_dir is given.
examples = []

OPT_MAIN_PATH = runfiles.get_path('xls/tools/opt_main')

# If there are any flags required for your setup, define them here.
# For instance, if you have the mentioned FLAGS like FLAGS.delay_model, you'll need to declare them.

# @app.route('/graph', methods=['POST'])
def read_file(file_path):
    with open(file_path, 'r') as f:
        return f.read()

def extract_and_construct_graph(text_content , file_top):
    try:
        json_text = ir_to_json.ir_to_json(text_content, "unit", 1, file_top)
        data = json.loads(json_text)

        # Hypothetical extraction process (this depends on the actual structure of your json_text)
        nodes_list = data['graph']['nodes']
        edges_list = data['graph']['edges']

        # Constructing a DGL graph
        g = dgl.graph((nodes_list, edges_list))

        # If using PyGEO, you'll construct the graph accordingly

        return g

    except Exception as e:
        print(f"Error: {str(e)}")
        return None

def main(argv):
    # Adjust with the path to your .ir file
    if len(sys.argv) > 1:
        file_path = sys.argv[1]  # This will be 'arg1' from your command
        file_top = sys.argv[2]  # This will be 'arg2' from your command
    # file_path = "//xls/tutorial/simple_add.ir" 
    # file_top = "add"
    text_content = read_file(file_path)
    graph = extract_and_construct_graph(text_content , file_top)
    # Further process or analyze the graph if necessary

if __name__ == '__main__':
    app.run(main)
