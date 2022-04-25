
ARITIES = {1: 'UNARY', 2: 'BINARY', 3: 'TERNARY'}

DTYPES = {'dt_int32': ('Int32', 'INT'),
          'dt_uint8': ('Uint8', 'INT'),
          'dt_int8': ('Int8', 'INT'),
          'dt_int16': ('Int16', 'INT'),
          'dt_bool': ('Bool', 'BOOL'),
          'dt_float32': ('Float32', 'FLOAT'),
          'dt_float16': ('Float16', 'FLOAT'),
          'dt_bfloat16': ('BFloat16', 'FLOAT')
          }

MODES = {
    (1, 'INT'): ['RELU', 'ABS', 'NEGATE', 'RELU6', 'SQUARE', 'SIGN'],
    (2, 'INT'): ['ABS_GRAD', 'ADD', 'FLOOR_DIV', 'MAX', 'MIN', 'MOD', 'MUL',
                 'SIGMOID_GRAD', 'SUB', 'SWITCH_GT0', 'TANH_GRAD', 'LT', 'LEQ',
                 'EQ', 'FUSE_ADD_RELU', 'SHL', 'SHR', 'RMULH', 'PRELU'],
    (3, 'INT'): ['COND_LEQ_MOV', 'COND_LT_MOV', 'CLIP'],

    (1, 'FLOAT'): ['RELU', 'ABS', 'NEGATE', 'ACOS', 'ASIN', 'CEIL', 'COS',
                   'EXP', 'EXPM1', 'FLOOR', 'LOG', 'LOG1P', 'SIGMOID', 'SIN',
                   'TANH', 'FAST_TANH', 'ROUND', 'ERF', 'ERFINV', 'ERFC',
                   'ERFCINV', 'H_SWISH', 'SILU', 'GELU', 'SINH', 'COSH',
                   'ASINH', 'ACOSH', 'ATANH', 'TAN', 'SOFTPLUS', 'RELU6',
                   'HSIGMOID', 'LOGSIGMOID', 'SQRT', 'SQUARE', 'SIGN'],
    (2, 'FLOAT'): ['ABS_GRAD', 'ADD', 'FLOOR_DIV', 'MAX', 'MIN', 'MOD', 'MUL',
                   'SIGMOID_GRAD', 'SUB', 'SWITCH_GT0', 'TANH_GRAD', 'LT',
                   'LEQ', 'EQ', 'FUSE_ADD_RELU', 'TRUE_DIV', 'POW',
                   'LOG_SUM_EXP', 'FUSE_ADD_TANH', 'FAST_TANH_GRAD',
                   'FUSE_ADD_SIGMOID', 'ATAN2', 'H_SWISH_GRAD',
                   'FUSE_ADD_H_SWISH', 'SILU_GRAD', 'GELU_GRAD', 'PRELU',
                   'ASINH_GRAD', 'ACOSH_GRAD', 'ATANH_GRAD', 'SOFTPLUS_GRAD',
                   'RELU6_GRAD', 'HSIGMOID_GRAD', 'SAFE_DIV'],
    (3, 'FLOAT'): ['COND_LEQ_MOV', 'COND_LT_MOV', 'FUSE_MUL_ADD3', 'CLIP', 'PRELU_GRAD'],
    (1, 'BOOL'): ['NOT'],
    (2, 'BOOL'): ['AND', 'OR', 'XOR', 'LT', 'LEQ', 'EQ'],
    (3, 'BOOL'): []
}
