#!/usr/bin/python

import argparse
import os
import sys
import yaml
#from pygments.lexer import default


def change_parameter(network, name, network_prefix):
        value = network[name].replace("172.16.0", network_prefix)
        network[name] = value

def main(args):
    config = None
    with open(args.config_file, 'r') as stream:
        config = yaml.load(stream)
    network_prefix = '172.18.' + args.env_number

    networking_parameters_config = config['networking_parameters']
    floating_ranges = []
    for ip_addresses in networking_parameters_config['floating_ranges']:
        ip_addresses = [ip.replace('172.16.0', network_prefix) for ip in ip_addresses]
        floating_ranges.append(ip_addresses)
    networking_parameters_config['floating_ranges'] = floating_ranges

    network_config = config['networks']
    for network in network_config:
        if network['name'] in ["public"]:
            change_parameter(network, 'gateway', network_prefix)
            change_parameter(network, 'cidr', network_prefix)
            ip_range = network['meta']['ip_range']
            ip_range = [ip.replace('172.16.0', network_prefix) for ip in ip_range]
            network['meta']['ip_range'] = ip_range

            ip_ranges = []
            for ip_addresses in network['ip_ranges']:
                ip_addresses = [ip.replace('172.16.0', network_prefix) for ip in ip_addresses]
                ip_ranges.append(ip_addresses)
            network['ip_ranges'] = ip_ranges

            if args.fuel_version not in ['8.0.0','9.0.0.0','10.0.0']:
                change_parameter(network['meta'], 'cidr', network_prefix)

    with open(args.config_file, 'w') as stream:
        stream.write(yaml.dump(config, default_flow_style=False))

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--fuel_version', dest='fuel_version', type=str, default='8.0.0')
    parser.add_argument('--config_file', dest='config_file', type=str, default='./network_1.yaml')
    parser.add_argument('--env_number', dest='env_number', type=str, default='0')

    main(parser.parse_args())


