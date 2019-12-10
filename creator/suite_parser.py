#!/bin/env python

import sys
import json
from robot.api import TestData

test_cases = []

def print_suite(suite):
    if suite.name is None:
        raise Exception('UndefinedSuite')
    for test in suite.testcase_table:
        if test is not None:
            tmp = {"name": '',"tags": [],"suite": str(suite.name),"steps":[]}
            tmp["name"] = str(test.name).replace(" ", "_")
            #for tag in test.tags:
            #    tmp["tags"].append(str(tag))
            append_state = True
            for tag_str in test.tags:
                if append_state:
                    tmp["tags"].append(tag_str)
                else:
                    tmp["tags"][-1] += " " + tag_str

                if "{" in tag_str and "}" not in tag_str:
                    if not append_state: tmp["tags"].append("ERROR State machine (1) broken")
                    append_state = False
                elif "}" in tag_str and "{" not in tag_str:
                    if append_state: tmp["tags"].append("ERROR State machine (2) broken")
                    append_state = True
            for step in test.steps:
                try:
                    tmp["steps"].append(str(step.name))
                except AttributeError:
                    pass
            test_cases.append(tmp)
    for child in suite.children:
        print_suite(child)

def print_suites(folder):
    suite = TestData(source=folder)
    print_suite(suite)
    if json.loads(json.dumps(test_cases)):
        print json.dumps(test_cases)

def get_suites(folder):
    return TestData(source=folder)

if __name__ == '__main__':
    print_suites(sys.argv[1])

