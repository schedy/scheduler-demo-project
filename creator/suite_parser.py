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
            for tag in test.tags:
                tmp["tags"].append(str(tag))
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
