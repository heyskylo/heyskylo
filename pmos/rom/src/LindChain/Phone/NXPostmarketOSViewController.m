            if (ok)
            {
                [weakSelf showRunning];
            }
            else
            {
                [weakSelf showFailureWithMessage:(error != nil ? error.localizedDescription
                                                              : @"the engine stopped unexpectedly")];
            }