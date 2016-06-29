#!/usr/bin/python

import argparse
import os
import sys
import yaml
#from pygments.lexer import default


def set_parameter(config, name, value):
    if value is not None:
        config[name] = value


def set_volume_size(name, size, volumes):
    for v in volumes:
        if name is None:
            v['size'] = size
        elif v['name'] == name:
           v['size'] = size
           break


def main(args):
    config = None
    with open(args.config_file, 'r') as stream:
        config = yaml.load(stream)
    
    devices = [ d.split('/')[-1] for d in args.device_paths.split(',') ]
    for i in config:
        for v in i['volumes']:
            if v['name'] == 'os':
                set_volume_size('cinder', 2000, i['volumes'])
                if args.is_controller:
                    set_volume_size('image', 20000, i['volumes'])
            if i['name'] in devices:
                set_volume_size(None, 0, i['volumes'])

    with open(args.config_file, 'w') as stream:
        stream.write(yaml.dump(config, default_flow_style=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--config_file', dest='config_file', type=str)
    parser.add_argument('--device_paths', dest='device_paths', type=str)
    parser.add_argument('--is_controller', dest='is_controller', type=bool)
    
    main(parser.parse_args())

