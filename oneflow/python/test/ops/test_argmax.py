import numpy as np
import tensorflow as tf
import oneflow as flow
from collections import OrderedDict

from test_util import GenArgList
from test_util import type_name_to_flow_type
from test_util import type_name_to_np_type

gpus = tf.config.experimental.list_physical_devices("GPU")
for gpu in gpus:
    tf.config.experimental.set_memory_growth(gpu, True)

def compare_with_tensorflow(device_type, in_shape, data_type):
    assert device_type in ["gpu", "cpu"]
    assert data_type in ["float32", "double", "int8", "int32", "int64"]
    flow.clear_default_session()
    func_config = flow.FunctionConfig()
    func_config.default_data_type(flow.float)

    @flow.function(func_config)
    def ArgMaxJob(
        input=flow.MirroredTensorDef(
            tuple([dim + 10 for dim in in_shape]), dtype=type_name_to_flow_type[data_type]
        )
    ):
        with flow.fixed_placement(device_type, "0:0"):
            return flow.math.argmax(input)

    input = (np.random.random(in_shape) * 100).astype(type_name_to_np_type[data_type])
    # OneFlow
    of_out = ArgMaxJob([input]).get().ndarray_list()[0]
    # TensorFlow
    tf_out = tf.math.argmax(input, -1).numpy()
    tf_out = np.array([tf_out]) if isinstance(tf_out, np.int64) else tf_out

    assert np.array_equal(of_out, tf_out)


def gen_arg_list():
    arg_dict = OrderedDict()
    arg_dict["device_type"] = ["gpu", "cpu"]
    arg_dict["in_shape"] = [(100,), (100, 100), (1000, 1000), (10, 10, 2000), (10, 10000)]
    arg_dict["data_type"] = ["float32", "double", "int32", "int64"]

    return GenArgList(arg_dict)


def test_argmax(test_case):
    for arg in gen_arg_list():
        compare_with_tensorflow(*arg)
