//
//  TransmitterViewController.m
//  transmitter
//
//  Created by Stephen Birarda on 5/13/13.
//  Copyright (c) 2013 High Fidelity, Inc. All rights reserved.
//

#import <CoreMotion/CoreMotion.h>

#import "TransmitterViewController.h"

@interface TransmitterViewController ()

@property (nonatomic, strong) CMMotionManager *motionManager;

@end

@implementation TransmitterViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self setupPairingSocket];
    
    // we want updates at 60Hz
    _motionManager.deviceMotionUpdateInterval = 1 / 60.0f;
    
    // start device motion updates
    [_motionManager startDeviceMotionUpdatesToQueue:[[NSOperationQueue alloc] init]
                                        withHandler:^(CMDeviceMotion *motion, NSError *error)
    {
        // setup a new packet with the gyro and accelerometer data
    }];
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

- (void)setupPairingSocket {
    
}

- (IBAction)pairButtonTapped:(id)sender {
    
}

@end
