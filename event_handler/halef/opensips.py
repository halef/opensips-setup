import logging
import xmlrpclib

class Opensips(object):
    def __init__(self, 
                xmlrpc_uri = 'http://127.0.0.1:8888/RPC2',
                probe_mode = 0,
                logger = None):
        self.xmlrpc_uri = xmlrpc_uri
        self.probe_mode = probe_mode
        self.logger = logger or logging.getLogger(__name__) 
    
    def opensips(self):
        return xmlrpclib.ServerProxy(self.xmlrpc_uri)
        
    def get_all_ids(self, only_enabled = False, subgroup = None):
        lb_list = self.opensips().lb_list()
 
        if 'Destination' in lb_list:
            destinations = [dst for dst in lb_list['Destination']]
            if subgroup:
                destinations = list(filter(
                    lambda dst: subgroup == dst['kids']['Resources']['kids']['Resource'][0]['value'], 
                    destinations)
                )
            if only_enabled:
                destinations = list(filter(
                    lambda dst: dst['attributes']['enabled'] == 'yes',
                    destinations
                ))
            return [dst['attributes']['id'] for dst in destinations]
        else:
            return []
    
    def reload_destinations(self):
        self.opensips().lb_reload()

    def disable_destination(self, destination_id):
        destination_id = str(destination_id)
        self.opensips().lb_status(destination_id, '0')

    def enable_destination(self, destination_id):
        destination_id = str(destination_id)
        self.opensips().lb_status(destination_id, '1')

    def get_id_by_ip(self, ip):
        lb_list = self.opensips().lb_list()

        if 'Destination' in lb_list:
            for dst in lb_list['Destination']:
                if ip == str(dst['value']).split(":")[1]:
                    return dst['attributes']['id']
        
        return None