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

typedef NS_ENUM(NSUInteger, TransmitterPairState) {
    TransmitterPairStateSleeping,
    TransmitterPairStatePairing,
    TransmitterPairStatePaired
};

@interface TransmitterViewController () <AsyncUdpSocketDelegate>

@property (strong, nonatomic) CMMotionManager *motionManager;
@property (strong, nonatomic) AsyncUdpSocket *transmitterSocket;
@property (strong, nonatomic) NSString *interfaceAddress;
@property (strong, nonatomic) UILongPressGestureRecognizer *longPressRecognizer;
@property (weak, nonatomic) IBOutlet UIButton *pairButton;
@property (weak, nonatomic) IBOutlet UIImageView *topPentagonImageView;
@property (weak, nonatomic) IBOutlet UIImageView *bottomPentagonImageView;
@property (weak, nonatomic) IBOutlet UILabel *pairedInfoLabel;
@property (nonatomic) UInt16 interfacePort;
@property (nonatomic) TransmitterPairState currentState;

@end

@implementation TransmitterViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // we want updates at 60Hz
    self.motionManager.deviceMotionUpdateInterval = 1 / 60.0f;
    
    // register for a notification when we go to the background
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleDidEnterBackground)
                                                 name:@"applicationDidEnterBackground"
                                               object:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    // rotate the bottom pentagon 180 degrees
    self.bottomPentagonImageView.transform = CGAffineTransformMakeRotation(180 * (M_PI / 180));
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

- (UILongPressGestureRecognizer *)longPressRecognizer {
    if (!_longPressRecognizer) {
        _longPressRecognizer = [[UILongPressGestureRecognizer alloc] init];
        _longPressRecognizer.minimumPressDuration = 0.01;
    }
    
    return _longPressRecognizer;
}

- (void)setCurrentState:(TransmitterPairState)currentState {
    if (currentState == TransmitterPairStatePairing) {
        [self.pairButton setImage:[UIImage imageNamed:@"cancel-pairing.png"] forState:UIControlStateNormal];
    } else {
        [self.pairButton setImage:nil forState:UIControlStateNormal];
    }
    
    if (currentState == TransmitterPairStatePaired) {
        self.pairButton.hidden = YES;
        self.pairedInfoLabel.text = [NSString stringWithFormat:@"%@ on %d", self.interfaceAddress, self.interfacePort];
        [UIApplication sharedApplication].idleTimerDisabled = YES;
        
        // add the long press gesture recognizer to the view
        [self.view addGestureRecognizer:self.longPressRecognizer];
    } else {
        self.pairButton.hidden = NO;
        self.pairedInfoLabel.text = nil;
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        // clear the interface client address and port
        self.interfaceAddress = nil;
        self.interfacePort = 0;
        
        // make sure the long press recognizer isn't attached to the view
        [self.view removeGestureRecognizer:self.longPressRecognizer];
    }
    
    _currentState = currentState;
}

#pragma mark - Backgrounding

- (void)handleDidEnterBackground {
    [self.motionManager stopDeviceMotionUpdates];
    self.transmitterSocket = nil;
    self.currentState = TransmitterPairStateSleeping;
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

                NSString *wifiInterface = [[[UIDevice currentDevice] model] hasSuffix:@"Simulator"]
                    ? @"en1"
                    : @"en0";
                
                // Check if interface is en0 which is the wifi connection on the iPhone
                if ([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:wifiInterface]) {
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

- (IBAction)pairButtonTapped:(UIButton *)sender {
    if (self.currentState != TransmitterPairStateSleeping) {
        
        if (self.currentState == TransmitterPairStatePaired) {
            // user wants to unpair the device
            NSLog(@"Unpairing - stopping device motion updates");
            
            // stop asking the motion manager for device motion updates
            [self.motionManager stopDeviceMotionUpdates];
        } else {
            NSLog(@"Cancelling the pair request");
        }
        
        // flip the pair button back to the right state
        self.currentState = TransmitterPairStateSleeping;
    } else {
        NSString* const PAIRING_SERVER_ADDRESS = @"pairing.highfidelity.io";
        UInt16 const PAIRING_SERVER_PORT = 7247;
        NSTimeInterval const PAIRING_RECEIVE_TIMEOUT = 5 * 60;
        
        [self.transmitterSocket sendData:[self pairRequestData]
                                  toHost:PAIRING_SERVER_ADDRESS
                                    port:PAIRING_SERVER_PORT
                             withTimeout:30
                                     tag:0];
        [self.transmitterSocket receiveWithTimeout:PAIRING_RECEIVE_TIMEOUT tag:0];
        
        self.currentState = TransmitterPairStatePairing;
    }
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
    
    NSLog(@"Pairing server has told us to talk to client at %@:%d", self.interfaceAddress, self.interfacePort);

    [self startMotionUpdates];
   
    return YES;
}

#pragma mark - Sensor Handling

- (void)startMotionUpdates {
    self.currentState = TransmitterPairStatePaired;
    
    if (!self.motionManager.isDeviceMotionActive) {
        NSLog(@"Staring device motion updates now");
        
        // start device motion updates
        [self.motionManager startDeviceMotionUpdatesToQueue:[[NSOperationQueue alloc] init]
                                                withHandler:^(CMDeviceMotion *motion, NSError *error)
         {
             // setup a new packet with the gyro and accelerometer data
             const char TRANSMITTER_PACKET_HEADER = 'T';
             const char TRANSMITTER_ROTATION_SEPARATOR = 'R';
             const char TRANSMITTER_ACCEL_SEPARATOR = 'A';
             const char TRANSMITTER_TOUCH_DOWN_SEPARATOR = 'D';
             const char TRANSMITTER_TOUCH_UP_SEPARATOR = 'U';
             
             NSMutableData *sensorData = [NSMutableData data];
             
             // append the transmitter packet header and then rotation data separator
             [sensorData appendBytes:&TRANSMITTER_PACKET_HEADER length:sizeof(TRANSMITTER_PACKET_HEADER)];
             [sensorData appendBytes:&TRANSMITTER_ROTATION_SEPARATOR length:sizeof(TRANSMITTER_ROTATION_SEPARATOR)];
             
             // cast each of the rotation doubles to a four byte float
             // convert them to degrees per second and swap Z and Y to match convention
             Float32 rotationRates[3];
             rotationRates[0] = (Float32) (motion.rotationRate.x * 180 / M_PI);
             rotationRates[1] = (Float32) (motion.rotationRate.z * 180 / M_PI);
             rotationRates[2] = (Float32) (motion.rotationRate.y * 180 / M_PI);
             
             // append the three floats for rotation
             [sensorData appendBytes:rotationRates length:sizeof(rotationRates)];
             
             // append the accelerometer data separator 
             [sensorData appendBytes:&TRANSMITTER_ACCEL_SEPARATOR length:sizeof(TRANSMITTER_ACCEL_SEPARATOR)];
             
             // cast each of the accelerometer doubles to a four byte float
             // the userAcceleration is corrected with gravity removed, add it back
             Float32 accelerations[3];
             accelerations[0] = (Float32) motion.userAcceleration.x + motion.gravity.x;
             accelerations[1] = (Float32) motion.userAcceleration.z + motion.gravity.z;
             accelerations[2] = (Float32) motion.userAcceleration.y + motion.gravity.y;
             
             // append the three floats for acceleration
             [sensorData appendBytes:accelerations length:sizeof(accelerations)];
             
             // send the state of touch, include point if finger is down
             CGPoint longPressPoint = [self.longPressRecognizer locationInView:self.view];
             
             if (!isnan(longPressPoint.x)) {
                 uint16_t touchPoints[2];
                 touchPoints[0] = (uint16_t) ((longPressPoint.x / self.view.frame.size.width) * UINT16_MAX);
                 touchPoints[1] = (uint16_t) (((self.view.frame.size.height - longPressPoint.y) /
                                              self.view.frame.size.height) * UINT16_MAX);
                 
                 [sensorData appendBytes:&TRANSMITTER_TOUCH_DOWN_SEPARATOR length:sizeof(TRANSMITTER_TOUCH_DOWN_SEPARATOR)];
                 [sensorData appendBytes:touchPoints length:sizeof(touchPoints)];                 
             } else {
                 [sensorData appendBytes:&TRANSMITTER_TOUCH_UP_SEPARATOR length:sizeof(TRANSMITTER_TOUCH_UP_SEPARATOR)];
             }
             
             dispatch_async(dispatch_get_main_queue(), ^{
                 // grab the state of the long press recognizer
                 
                 if (self.interfaceAddress) {                     
                     // send the prepared packet to the interface client we are paired to
                     [self.transmitterSocket sendData:sensorData
                                               toHost:self.interfaceAddress
                                                 port:self.interfacePort
                                          withTimeout:30
                                                  tag:0];
                 }
             });             
         }];
    }
}

@end
