#!/usr/bin/python

import argparse
import os
import sys
import yaml
#from pygments.lexer import default


def set_parameter(config, name, value):
    if value is not None:
        config[name]['value'] = value


def main(args):
    config = None
    with open(args.config_file, 'r') as stream:
        config = yaml.load(stream)
    if args.fuel_version != '8.0.0':
        scaleio_config = config['editable']['scaleio']
        scaleio_config['metadata']['enabled'] = True
    else:
        scaleio_config = config['editable']['scaleio']['metadata']
        scaleio_config['enabled'] = True
        scaleio_config = scaleio_config['versions'][0]
    set_parameter(scaleio_config, 'password', args.password)
    set_parameter(scaleio_config, 'protection_domain_nodes', args.protection_domain_nodes)
    set_parameter(scaleio_config, 'device_paths', args.device_paths)
    set_parameter(scaleio_config, 'rfcache_devices', args.rfcache_devices)
    set_parameter(scaleio_config, 'storage_pools', args.storage_pools)
    set_parameter(scaleio_config, 'cached_storage_pools', args.cached_storage_pools)
    set_parameter(scaleio_config, 'sds_on_controller', args.sds_on_controller)
    set_parameter(scaleio_config, 'zero_padding', args.zero_padding)
    set_parameter(scaleio_config, 'scanner_mode', args.scanner_mode)
    set_parameter(scaleio_config, 'checksum_mode', args.checksum_mode)
    set_parameter(scaleio_config, 'spare_policy', args.spare_policy)
    with open(args.config_file, 'w') as stream:
        stream.write(yaml.dump(config, default_flow_style=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--fuel_version', dest='fuel_version', type=str, default='8.0')
    parser.add_argument('--config_file', dest='config_file', type=str, default='./settings_1.yaml')
    parser.add_argument('--password', dest='password', type=str, default='qwe123QWE')
    parser.add_argument('--device_paths', dest='device_paths', type=str, default=None)
    parser.add_argument('--protection_domain_nodes', dest='protection_domain_nodes', type=str, default=None)
    parser.add_argument('--storage_pools', dest='storage_pools', type=str, default=None)
    parser.add_argument('--sds_on_controller', dest='sds_on_controller', type=bool, default=None)
    parser.add_argument('--zero_padding', dest='zero_padding', type=bool, default=None)
    parser.add_argument('--scanner_mode', dest='scanner_mode', type=bool, default=None)
    parser.add_argument('--spare_policy', dest='spare_policy', type=bool, default=None)
    parser.add_argument('--checksum_mode', dest='checksum_mode', type=bool, default=None)
    parser.add_argument('--rfcache_devices', dest='rfcache_devices', type=str, default=None)
    parser.add_argument('--storage_roles', dest='storage_roles', type=str, default=None)
    parser.add_argument('--cached_storage_pools', dest='cached_storage_pools', type=str, default=None)
    
    
    main(parser.parse_args())
