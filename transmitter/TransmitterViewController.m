//
//  TransmitterViewController.m
//  transmitter
//
//  Created by Stephen Birarda on 5/13/13.
//  Copyright (c) 2013 High Fidelity, Inc. All rights reserved.
//

#import <CoreMotion/CoreMotion.h>
#import <AsyncUdpSocket.h>
#include <ifaddrs.h>
#include <arpa/inet.h>

#import "TransmitterViewController.h"

@interface TransmitterViewController () <AsyncUdpSocketDelegate>

@property (nonatomic, strong) CMMotionManager *motionManager;
@property (nonatomic, strong) AsyncUdpSocket *transmitterSocket;
@property (nonatomic, strong) NSString *interfaceAddress;
@property (nonatomic) UInt16 interfacePort;

@end

@implementation TransmitterViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // we want updates at 60Hz
    self.motionManager.deviceMotionUpdateInterval = 1 / 60.0f;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (CMMotionManager *)motionManager {
    if (!_motionManager) {
        _motionManager = [[CMMotionManager alloc] init];
    }
    
    return _motionManager;
}

- (AsyncUdpSocket *)transmitterSocket {    
    if (!_transmitterSocket) {
        
        UInt16 const TRANSMITTER_BIND_PORT = 6472;
        
        _transmitterSocket = [[AsyncUdpSocket alloc] initWithDelegate:self];
        
        if ([_transmitterSocket bindToPort:TRANSMITTER_BIND_PORT error:nil]) {
            NSLog(@"Socket successfully bound to port %d", _transmitterSocket.localPort);
        }
    }
    
    return _transmitterSocket;
}

#pragma mark - Pairing

- (NSString *)wifiIPAddress {
    // the following is a copy-paste from
    // http://blog.zachwaugh.com/post/309927273/programmatically-retrieving-ip-address-of-iphone
    
    NSString *address = @"error";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = 0;
    
    // retrieve the current interfaces - returns 0 on success
    success = getifaddrs(&interfaces);
    if (success == 0) {
        // Loop through linked list of interfaces
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if( temp_addr->ifa_addr->sa_family == AF_INET) {
                // Check if interface is en0 which is the wifi connection on the iPhone
                if ([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
                    // Get NSString from C String
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                }
            }
            
            temp_addr = temp_addr->ifa_next;
        }
    }
    
    // Free memory
    freeifaddrs(interfaces);
    
    return address;
}

- (NSData *)pairRequestData {
    static NSData *pairRequestData = nil;
    
    if (!pairRequestData) {
        NSString *pairRequestString = [NSString stringWithFormat:@"Available iOS-Transmitter %@:%d",
                                       [self wifiIPAddress],
                                       _transmitterSocket.localPort];
        pairRequestData = [pairRequestString dataUsingEncoding:NSNonLossyASCIIStringEncoding];
    }
    
    return pairRequestData;
}

- (IBAction)pairButtonTapped:(id)sender {
    NSString* const PAIRING_SERVER_ADDRESS = @"pairing.highfidelity.io";
    UInt16 const PAIRING_SERVER_PORT = 7247;
    NSTimeInterval const PAIRING_RECEIVE_TIMEOUT = 5 * 60;
    
    [self.transmitterSocket sendData:[self pairRequestData]
                              toHost:PAIRING_SERVER_ADDRESS
                                port:PAIRING_SERVER_PORT
                         withTimeout:30
                                 tag:0];
    [self.transmitterSocket receiveWithTimeout:PAIRING_RECEIVE_TIMEOUT tag:0];
}

- (BOOL)onUdpSocket:(AsyncUdpSocket *)sock
     didReceiveData:(NSData *)data
            withTag:(long)tag
           fromHost:(NSString *)host
               port:(UInt16)port {
    
    NSString *interfaceSocketString = [[NSString alloc] initWithData:data encoding:NSNonLossyASCIIStringEncoding];
    NSRange colonRange = [interfaceSocketString rangeOfString:@":"];
    
    self.interfaceAddress = [interfaceSocketString substringToIndex:colonRange.location];
    self.interfacePort = [[interfaceSocketString substringFromIndex:colonRange.location + 1] integerValue];
    [self startMotionUpdates];
   
    return YES;
}

#pragma mark - Sensor Handling
- (void)startMotionUpdates {
    if (!self.motionManager.isDeviceMotionActive) {
        // start device motion updates
        [self.motionManager startDeviceMotionUpdatesToQueue:[[NSOperationQueue alloc] init]
                                                withHandler:^(CMDeviceMotion *motion, NSError *error)
         {
             // setup a new packet with the gyro and accelerometer data
             const char TRANSMITTER_PACKET_HEADER = 'T';
             const char TRANSMITTER_ROTATION_SEPARATOR = 'R';
             const char TRANSMITTER_ACCEL_SEPARATOR = 'A';
             
             NSMutableData *sensorData = [NSMutableData data];
             
             // append the transmitter packet header and then rotation data separator
             [sensorData appendBytes:&TRANSMITTER_PACKET_HEADER length:sizeof(TRANSMITTER_PACKET_HEADER)];
             [sensorData appendBytes:&TRANSMITTER_ROTATION_SEPARATOR length:sizeof(TRANSMITTER_ROTATION_SEPARATOR)];
             
             // cast each of the rotation doubles to a four byte float
             Float32 rotationRates[3];
             rotationRates[0] = (Float32) motion.rotationRate.x;
             rotationRates[1] = (Float32) motion.rotationRate.y;
             rotationRates[2] = (Float32) motion.rotationRate.z;
             
             // append the three floats for rotation
             [sensorData appendBytes:rotationRates length:sizeof(rotationRates)];
             
             // append the accelerometer data separator 
             [sensorData appendBytes:&TRANSMITTER_ACCEL_SEPARATOR length:sizeof(TRANSMITTER_ACCEL_SEPARATOR)];
             
             // cast each of the accelerometer doubles to a four byte float
             Float32 accelerations[3];
             accelerations[0] = (Float32) motion.userAcceleration.x;
             accelerations[1] = (Float32) motion.userAcceleration.y;
             accelerations[2] = (Float32) motion.userAcceleration.z;
             
             // append the three floats for acceleration
             [sensorData appendBytes:accelerations length:sizeof(accelerations)];
             
             // send the prepared packet to the interface client we are paired to
             [self.transmitterSocket sendData:sensorData
                                       toHost:self.interfaceAddress
                                         port:self.interfacePort
                                  withTimeout:30
                                          tag:0];
         }];
    }
}

@end
