#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json
import sys
import os
import base64
import datetime
import hashlib
import hmac
import urllib.parse
import requests
import time
from urllib.request import urlopen
import socket

def sign(key, msg):
    return hmac.new(key, msg.encode('utf-8'), hashlib.sha256).digest()

def get_ntp_time():
    """通过NTP协议获取网络时间"""
    try:
        # NTP服务器列表
        ntp_servers = [
            'pool.ntp.org',
            'time.google.com',
            'time.windows.com', 
            'time.apple.com',
            'time.nist.gov'
        ]
        
        for server in ntp_servers:
            try:
                # NTP请求包格式
                client = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                client.settimeout(3.0)
                
                # NTP请求报文
                data = b'\x1b' + 47 * b'\0'
                
                client.sendto(data, (server, 123))
                data, _ = client.recvfrom(1024)
                
                if data:
                    # 解析NTP响应
                    t = int.from_bytes(data[40:44], byteorder='big')
                    # 时间戳从1900年开始，需要减去70年的秒数
                    t -= 2208988800
                    client.close()
                    return t
            except:
                continue
        
        return None
    except:
        return None

def get_http_time():
    """通过HTTP头获取网络时间"""
    time_servers = [
        'https://www.google.com',
        'https://www.baidu.com',
        'https://www.microsoft.com',
        'https://www.apple.com',
        'https://cloud.tencent.com',
        'https://dnspod.tencentcloudapi.com'
    ]
    
    for url in time_servers:
        try:
            response = requests.head(url, timeout=3)
            if 'date' in response.headers:
                date_str = response.headers['date']
                return int(time.mktime(time.strptime(date_str, "%a, %d %b %Y %H:%M:%S GMT")) + time.timezone)
        except:
            continue
    
    return None

def get_server_time():
    """获取服务器时间，尝试多种方法"""
    # 首先尝试NTP时间
    ntp_time = get_ntp_time()
    if ntp_time:
        return ntp_time
    
    # 然后尝试HTTP时间
    http_time = get_http_time()
    if http_time:
        return http_time
    
    # 都失败时使用本地时间
    local_time = int(time.time())
    return local_time

def get_signature(action, params, secret_id, secret_key):
    canonical_uri = '/'
    canonical_querystring = ''
    ct = 'application/json'
    host = 'dnspod.tencentcloudapi.com'
    algorithm = 'TC3-HMAC-SHA256'
    
    # 获取服务器时间戳，避免时间不同步问题
    timestamp = get_server_time()
    date = datetime.datetime.fromtimestamp(timestamp, tz=datetime.timezone.utc).strftime('%Y-%m-%d')
    
    # 准备请求头部
    service = 'dnspod'
    headers = {
        'Content-Type': ct,
        'Host': host,
        'X-TC-Action': action,
        'X-TC-Timestamp': str(timestamp),
        'X-TC-Version': '2021-03-23',
        'X-TC-Region': 'ap-guangzhou'
    }
    
    # 移除认证相关参数
    payload_params = params.copy()
    if 'SecretId' in payload_params:
        del payload_params['SecretId']
    if 'Action' in payload_params:
        del payload_params['Action']
    
    # 准备签名参数
    signed_headers = 'content-type;host'
    payload = json.dumps(payload_params)
    
    hashed_request_payload = hashlib.sha256(payload.encode('utf-8')).hexdigest()
    canonical_request = ("POST\n" +
                         canonical_uri + '\n' +
                         canonical_querystring + '\n' +
                         'content-type:' + ct + '\n' +
                         'host:' + host + '\n' +
                         '\n' +
                         signed_headers + '\n' +
                         hashed_request_payload)

    hashed_canonical_request = hashlib.sha256(canonical_request.encode('utf-8')).hexdigest()
    credential_scope = date + '/' + service + '/tc3_request'
    string_to_sign = (algorithm + '\n' +  
                      str(timestamp) + '\n' +  
                      credential_scope + '\n' +  
                      hashed_canonical_request)

    # 计算签名
    secret_date = sign(('TC3' + secret_key).encode('utf-8'), date)
    secret_service = sign(secret_date, service)
    secret_signing = sign(secret_service, 'tc3_request')
    signature = hmac.new(secret_signing, string_to_sign.encode('utf-8'), hashlib.sha256).hexdigest()
    
    # 组装授权信息
    authorization = (algorithm + ' ' + 
                    'Credential=' + secret_id + '/' + credential_scope + ', ' +
                    'SignedHeaders=' + signed_headers + ', ' + 
                    'Signature=' + signature)
    
    headers['Authorization'] = authorization
    return headers, payload, timestamp

def api_call(action, params, secret_id, secret_key):
    # 从参数中移除认证相关参数并在header中使用
    headers, payload, timestamp = get_signature(action, params, secret_id, secret_key)
    
    try:
        response = requests.post("https://dnspod.tencentcloudapi.com/", 
                                 headers=headers, 
                                 data=payload,
                                 timeout=10)
        return response.text
    except Exception as e:
        return json.dumps({"Error": str(e)})

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 dnspod_api.py <action> [params]")
        sys.exit(1)
    
    action = sys.argv[1]
    params_raw = sys.argv[2] if len(sys.argv) > 2 else "{}"
    
    # 获取环境变量中的密钥
    secret_id = os.environ.get('DNSPOD_SECRET_ID')
    secret_key = os.environ.get('DNSPOD_SECRET_KEY')
    
    if not secret_id or not secret_key:
        print(json.dumps({"Error": "环境变量 DNSPOD_SECRET_ID 或 DNSPOD_SECRET_KEY 未设置"}))
        sys.exit(1)
    
    # 解析参数
    try:
        params = json.loads(params_raw)
    except:
        print(json.dumps({"Error": "参数格式错误，请使用JSON格式"}))
        sys.exit(1)
    
    # 调用API并返回结果
    result = api_call(action, params, secret_id, secret_key)
    print(result)
