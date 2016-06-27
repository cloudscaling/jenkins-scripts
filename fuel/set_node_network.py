#!/usr/bin/python

import argparse
import os
import sys
import yaml
#from pygments.lexer import default


def main(args):
    config = None
    with open(args.config_file, 'r') as stream:
        config = yaml.load(stream)
    
    to_move = []
    for interface in config:
        if interface['name'] == 'eth0':
            for network in interface['assigned_networks']:
                if network['name'] != 'fuelweb_admin':
                    to_move.append(network)
        for net in to_move:
            interface['assigned_networks'].remove(net)
        break
    
    for interface in config:
        if interface['name'] == 'eth1':
            interface['assigned_networks'] += to_move
            break

    with open(args.config_file, 'w') as stream:
        stream.write(yaml.dump(config, default_flow_style=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--config_file', dest='config_file', type=str)
    
    main(parser.parse_args())

