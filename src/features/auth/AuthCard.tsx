import React from 'react';
import { Box, Card, CardContent, Typography } from '@mui/material';
import { ORG_CONFIG } from '@/config/constants';

export const AuthCard: React.FC<{ title: string; subtitle: string; children: React.ReactNode }> = ({
  title,
  subtitle,
  children,
}) => (
  <Box sx={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', bgcolor: '#081e38', p: 2 }}>
    <Card sx={{ maxWidth: 440, width: '100%', borderRadius: 3, boxShadow: 6 }}>
      <CardContent sx={{ p: 4 }}>
        <Box component="img" src="/pathology-logo.png" alt="Bimal Pathology Logo" sx={{ width: 72, height: 72, objectFit: 'contain', mx: 'auto', mb: 1.5, display: 'block' }} />
        <Typography variant="h6" fontWeight={800} color="primary.main" textAlign="center">
          {ORG_CONFIG.nameEn}
        </Typography>
        <Typography variant="h5" fontWeight={800} textAlign="center" sx={{ mt: 2 }}>
          {title}
        </Typography>
        <Typography variant="body2" color="text.secondary" textAlign="center" sx={{ mt: 0.75, mb: 3 }}>
          {subtitle}
        </Typography>
        {children}
      </CardContent>
    </Card>
  </Box>
);
