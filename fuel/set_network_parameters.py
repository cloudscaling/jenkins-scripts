#!/usr/bin/python

import argparse
import os
import sys
import yaml
#from pygments.lexer import default


def change_parameter(network, name):
        value = network[name].replace("172.16.0","172.18.0")
        network[name] = value

def main(args):
    config = None
    with open(args.config_file, 'r') as stream:
        config = yaml.load(stream)

    networking_parameters_config = config['networking_parameters']
    floating_ranges = []
    for ip_addresses in networking_parameters_config['floating_ranges']:
        ip_addresses = [ip.replace('172.16.0', '172.18.0') for ip in ip_addresses]
        floating_ranges.append(ip_addresses)
    networking_parameters_config['floating_ranges'] = floating_ranges

    network_config = config['networks']
    for network in network_config:
        if network['name'] in ["public"]:
            change_parameter(network, 'gateway')
            change_parameter(network, 'cidr')
            ip_range = network['meta']['ip_range']
            ip_range = [ip.replace('172.16.0', '172.18.0') for ip in ip_range]
            network['meta']['ip_range'] = ip_range

            ip_ranges = []
            for ip_addresses in network['ip_ranges']:
                ip_addresses = [ip.replace('172.16.0', '172.18.0') for ip in ip_addresses]
                ip_ranges.append(ip_addresses)
            network['ip_ranges'] = ip_ranges

    with open(args.config_file, 'w') as stream:
        stream.write(yaml.dump(config, default_flow_style=False))

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--config_file', dest='config_file', type=str, default='./network_1.yaml')

    main(parser.parse_args())
