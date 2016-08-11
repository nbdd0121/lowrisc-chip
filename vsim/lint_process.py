#!/usr/bin/env python
import re
from sys import exit
from sys import stdin

def import_ignore_rules() :
    return map(lambda x: x.rstrip(), open('ignore_rules.regex').readlines())

print('Processing lint output')
temp_lines = []
for line in stdin:
    matched_a_regex = False
    for regex_rule in import_ignore_rules():
        m = re.search(regex_rule, line.rstrip())
        if m is not None:
            matched_a_regex = True
            error_type = m.group(1)
            if error_type == '%Warning-WIDTH':
                size_a = int(m.group(2))
                size_b = int(m.group(5))
                const = m.group(3)
                expectation = m.group(4)
                if const is not None:
                    temp_lines.append(line)
                else:
                    if (size_a > size_b):
                        temp_lines.append(line)
    if not matched_a_regex:
        temp_lines.append(line)

with open('verilator.lint','wb') as out_fh:
    for out_line in temp_lines:
        out_fh.write(out_line)

print('Warning from non-generated sources: ' + str(len(temp_lines) - 1))
if len(temp_lines) > 1:
    exit(1)
